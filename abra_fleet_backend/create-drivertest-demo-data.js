// create-drivertest-demo-data.js
// Creates comprehensive demo data for drivertest@gmail.com for manager demo

const { MongoClient, ObjectId } = require('mongodb');
const admin = require('firebase-admin');

// MongoDB connection
const MONGO_URI = 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';
const DB_NAME = 'abra_fleet';

// Initialize Firebase Admin if not already initialized
if (!admin.apps.length) {
  try {
    const serviceAccount = require('./serviceAccountKey.json');
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      databaseURL: 'https://abra-fleet-default-rtdb.firebaseio.com'
    });
  } catch (error) {
    console.log('Firebase already initialized or service account not found');
  }
}

async function createDriverTestDemoData() {
  console.log('\n🚗 ========== CREATING DRIVERTEST DEMO DATA ==========\n');
  
  const client = new MongoClient(MONGO_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db(DB_NAME);
    
    // Collections
    const driversCollection = db.collection('drivers');
    const usersCollection = db.collection('users');
    const tripsCollection = db.collection('trips');
    const vehiclesCollection = db.collection('vehicles');
    const rostersCollection = db.collection('rosters');
    const adminUsersCollection = db.collection('admin_users');
    
    const driverEmail = 'drivertest@gmail.com';
    const customerEmail = 'customer123@abrafleet.com';
    
    console.log('🔍 Setting up demo data for:', driverEmail);
    
    // 1. Create/Update Driver Profile
    console.log('\n📝 1. Creating driver profile...');
    const driverData = {
      driverId: 'DRV001',
      personalInfo: {
        firstName: 'Rajesh',
        lastName: 'Kumar',
        email: driverEmail,
        phone: '+91 9876543210',
        dateOfBirth: '1985-03-15',
        address: {
          street: '123 MG Road',
          city: 'Bangalore',
          state: 'Karnataka',
          pincode: '560001',
          country: 'India'
        }
      },
      license: {
        licenseNumber: 'KA0320190012345',
        licenseType: 'Commercial',
        issueDate: '2019-01-15',
        expiryDate: '2029-01-15',
        issuingAuthority: 'Karnataka RTO'
      },
      experience: {
        totalYears: 8,
        commercialYears: 5,
        previousEmployers: ['City Cabs', 'Metro Transport']
      },
      documents: [
        {
          type: 'license',
          fileName: 'driving_license.pdf',
          uploadDate: new Date('2024-01-15'),
          status: 'verified',
          expiryDate: '2029-01-15'
        },
        {
          type: 'aadhar',
          fileName: 'aadhar_card.pdf',
          uploadDate: new Date('2024-01-15'),
          status: 'verified'
        },
        {
          type: 'pan',
          fileName: 'pan_card.pdf',
          uploadDate: new Date('2024-01-15'),
          status: 'verified'
        }
      ],
      assignedVehicle: 'VH001',
      status: 'active',
      rating: 4.8,
      totalTrips: 245,
      joinedDate: new Date('2024-01-15'),
      createdAt: new Date('2024-01-15'),
      updatedAt: new Date(),
      uid: null // Will be set after Firebase user creation
    };
    
    // Create Firebase user for driver if not exists
    let firebaseUid = null;
    try {
      const existingUser = await admin.auth().getUserByEmail(driverEmail);
      firebaseUid = existingUser.uid;
      console.log('✅ Found existing Firebase user:', firebaseUid);
    } catch (error) {
      // Create new Firebase user
      const firebaseUser = await admin.auth().createUser({
        email: driverEmail,
        emailVerified: true,
        password: 'Driver123!',
        displayName: 'Rajesh Kumar',
        disabled: false
      });
      firebaseUid = firebaseUser.uid;
      
      // Set custom claims
      await admin.auth().setCustomUserClaims(firebaseUid, {
        role: 'driver',
        driverId: 'DRV001'
      });
      
      console.log('✅ Created Firebase user:', firebaseUid);
    }
    
    driverData.uid = firebaseUid;
    driverData.firebaseUid = firebaseUid;
    
    await driversCollection.replaceOne(
      { 'personalInfo.email': driverEmail },
      driverData,
      { upsert: true }
    );
    console.log('✅ Driver profile created/updated');
    
    // Create admin_users entry
    await adminUsersCollection.replaceOne(
      { email: driverEmail },
      {
        firebaseUid: firebaseUid,
        email: driverEmail,
        name: 'Rajesh Kumar',
        role: 'driver',
        phone: '+91 9876543210',
        status: 'active',
        driverId: 'DRV001',
        modules: [],
        permissions: {},
        createdAt: new Date('2024-01-15'),
        updatedAt: new Date(),
        lastActive: new Date()
      },
      { upsert: true }
    );
    
    // 2. Create Demo Vehicle
    console.log('\n🚙 2. Creating demo vehicle...');
    const vehicleData = {
      vehicleId: 'VH001',
      registrationNumber: 'KA01AB1234',
      make: 'Maruti',
      model: 'Eeco',
      year: 2023,
      type: 'Van',
      fuelType: 'Petrol',
      capacity: 4,
      color: 'White',
      chassisNumber: 'MAT123456789',
      engineNumber: 'ENG987654321',
      insurance: {
        policyNumber: 'INS123456789',
        provider: 'HDFC ERGO',
        expiryDate: '2025-06-15',
        status: 'active'
      },
      fitness: {
        certificateNumber: 'FIT123456',
        expiryDate: '2025-03-20',
        status: 'valid'
      },
      pollution: {
        certificateNumber: 'PUC123456',
        expiryDate: '2024-12-30',
        status: 'valid'
      },
      assignedDriver: 'DRV001',
      status: 'active',
      organization: 'ABRA_FLEET',
      vendor: 'Fleet Solutions Pvt Ltd',
      purchaseDate: '2022-04-15',
      currentMileage: 45230,
      lastServiceDate: '2024-11-15',
      nextServiceDue: '2025-02-15',
      createdAt: new Date('2022-04-15'),
      updatedAt: new Date()
    };
    
    await db.collection('vehicles').replaceOne(
      { vehicleId: 'VH001' },
      vehicleData,
      { upsert: true }
    );
    console.log('✅ Demo vehicle created');
    
    // 3. Create Demo Customer
    console.log('\n👤 3. Creating demo customer...');
    
    // Create Firebase user for customer if not exists
    let customerFirebaseUid = null;
    try {
      const existingCustomer = await admin.auth().getUserByEmail(customerEmail);
      customerFirebaseUid = existingCustomer.uid;
      console.log('✅ Found existing customer Firebase user:', customerFirebaseUid);
    } catch (error) {
      // Create new Firebase user
      const customerFirebaseUser = await admin.auth().createUser({
        email: customerEmail,
        emailVerified: true,
        password: 'Customer123!',
        displayName: 'Priya Sharma',
        disabled: false
      });
      customerFirebaseUid = customerFirebaseUser.uid;
      
      // Set custom claims
      await admin.auth().setCustomUserClaims(customerFirebaseUid, {
        role: 'customer'
      });
      
      console.log('✅ Created customer Firebase user:', customerFirebaseUid);
    }
    
    const customerData = {
      uid: customerFirebaseUid,
      email: customerEmail,
      name: 'Priya Sharma',
      phone: '+91 9123456789',
      organization: 'ABRA_FLEET',
      employeeId: 'EMP123',
      department: 'IT',
      designation: 'Software Engineer',
      addresses: {
        home: {
          address: '456 Koramangala, Bangalore, Karnataka 560034',
          latitude: 12.9352,
          longitude: 77.6245,
          type: 'home'
        },
        office: {
          address: 'Manyata Tech Park, Bangalore, Karnataka 560045',
          latitude: 13.0389,
          longitude: 77.6197,
          type: 'office'
        }
      },
      currentAddress: 'home',
      status: 'active',
      joinedDate: new Date('2024-02-01'),
      createdAt: new Date('2024-02-01'),
      updatedAt: new Date()
    };
    
    await usersCollection.replaceOne(
      { email: customerEmail },
      customerData,
      { upsert: true }
    );
    console.log('✅ Demo customer created');
    
    // Get customer ObjectId for trip creation
    const customer = await usersCollection.findOne({ email: customerEmail });
    const driver = await driversCollection.findOne({ 'personalInfo.email': driverEmail });
    const vehicle = await db.collection('vehicles').findOne({ vehicleId: 'VH001' });
    
    // 4. Create Active Trip
    console.log('\n🚗 4. Creating active trip...');
    const tripData = {
      tripNumber: 'TR' + Date.now().toString().slice(-6),
      customerId: customer._id,
      driverId: driver._id,
      vehicleId: vehicle._id,
      pickupLocation: {
        address: '456 Koramangala, Bangalore, Karnataka 560034',
        latitude: 12.9352,
        longitude: 77.6245,
        type: 'home'
      },
      dropLocation: {
        address: 'Manyata Tech Park, Bangalore, Karnataka 560045',
        latitude: 13.0389,
        longitude: 77.6197,
        type: 'office'
      },
      scheduledPickupTime: new Date(Date.now() + 30 * 60 * 1000), // 30 minutes from now
      actualPickupTime: new Date(),
      estimatedDropTime: new Date(Date.now() + 90 * 60 * 1000), // 90 minutes from now
      distance: 18.5,
      estimatedDuration: 45,
      status: 'in_progress',
      tripType: 'scheduled',
      fare: {
        baseFare: 150,
        distanceFare: 185,
        totalFare: 335,
        currency: 'INR'
      },
      route: {
        waypoints: [
          { latitude: 12.9352, longitude: 77.6245, address: 'Koramangala' },
          { latitude: 12.9716, longitude: 77.5946, address: 'MG Road' },
          { latitude: 13.0067, longitude: 77.6033, address: 'Cubbon Park' },
          { latitude: 13.0389, longitude: 77.6197, address: 'Manyata Tech Park' }
        ],
        totalDistance: 18.5,
        estimatedTime: 45
      },
      currentLocation: {
        latitude: 12.9716,
        longitude: 77.5946,
        timestamp: new Date(),
        speed: 35,
        heading: 45
      },
      organization: 'ABRA_FLEET',
      createdAt: new Date(),
      updatedAt: new Date()
    };
    
    const tripResult = await tripsCollection.insertOne(tripData);
    console.log('✅ Active trip created:', tripResult.insertedId);
    
    // 5. Create Today's Route with Multiple Customers
    console.log('\n📍 5. Creating today\'s route with customers...');
    
    // Create additional demo customers for the route
    const additionalCustomers = [
      {
        name: 'Amit Patel',
        email: 'amit.patel@abrafleet.com',
        phone: '+91 9234567890',
        address: 'Electronic City, Bangalore',
        latitude: 12.8456,
        longitude: 77.6603,
        status: 'completed',
        pickupTime: '08:30 AM',
        sequence: 1
      },
      {
        name: 'Sneha Reddy',
        email: 'sneha.reddy@abrafleet.com', 
        phone: '+91 9345678901',
        address: 'Whitefield, Bangalore',
        latitude: 12.9698,
        longitude: 77.7500,
        status: 'picked_up',
        pickupTime: '09:15 AM',
        sequence: 2
      },
      {
        name: 'Priya Sharma',
        email: customerEmail,
        phone: '+91 9123456789',
        address: 'Koramangala, Bangalore',
        latitude: 12.9352,
        longitude: 77.6245,
        status: 'in_progress',
        pickupTime: '09:45 AM',
        sequence: 3
      }
    ];
    
    // Create roster for today
    const todayRoster = {
      rosterId: 'RST' + Date.now().toString().slice(-6),
      driverId: driver._id,
      vehicleId: vehicle._id,
      date: new Date().toISOString().split('T')[0],
      shift: 'morning',
      route: {
        startLocation: {
          address: 'Fleet Depot, Bangalore',
          latitude: 12.9141,
          longitude: 77.6101
        },
        endLocation: {
          address: 'Manyata Tech Park, Bangalore',
          latitude: 13.0389,
          longitude: 77.6197
        },
        totalDistance: 35.8,
        estimatedDuration: 90
      },
      customers: additionalCustomers.slice(0, 3), // Only 3 customers for 4-seater vehicle
      status: 'active',
      startTime: new Date().setHours(8, 0, 0, 0),
      endTime: new Date().setHours(18, 0, 0, 0),
      organization: 'ABRA_FLEET',
      createdAt: new Date(),
      updatedAt: new Date()
    };
    
    await rostersCollection.replaceOne(
      { 
        driverId: driver._id,
        date: new Date().toISOString().split('T')[0]
      },
      todayRoster,
      { upsert: true }
    );
    console.log('✅ Today\'s route created with customers');
    
    // 6. Create Historical Trip Data for Stats
    console.log('\n📊 6. Creating historical trip data for stats...');
    
    const today = new Date();
    const thisMonth = new Date(today.getFullYear(), today.getMonth(), 1);
    
    // Create completed trips for this month
    const historicalTrips = [];
    for (let i = 1; i <= 15; i++) {
      const tripDate = new Date(thisMonth);
      tripDate.setDate(i);
      
      historicalTrips.push({
        tripNumber: 'TR' + (Date.now() + i).toString().slice(-6),
        customerId: customer._id,
        driverId: driver._id,
        vehicleId: vehicle._id,
        pickupLocation: {
          address: 'Various pickup locations',
          latitude: 12.9352 + (Math.random() - 0.5) * 0.1,
          longitude: 77.6245 + (Math.random() - 0.5) * 0.1
        },
        dropLocation: {
          address: 'Various drop locations',
          latitude: 13.0389 + (Math.random() - 0.5) * 0.1,
          longitude: 77.6197 + (Math.random() - 0.5) * 0.1
        },
        distance: 15 + Math.random() * 20,
        status: 'completed',
        actualPickupTime: new Date(tripDate.getTime() + 8 * 60 * 60 * 1000),
        actualDropTime: new Date(tripDate.getTime() + 9 * 60 * 60 * 1000),
        rating: 4 + Math.random(),
        organization: 'ABRA_FLEET',
        createdAt: tripDate,
        updatedAt: tripDate
      });
    }
    
    await tripsCollection.insertMany(historicalTrips);
    console.log('✅ Historical trips created for stats');
    
    // 7. Create SOS History
    console.log('\n🚨 7. Creating SOS alert history...');
    
    const sosHistory = [
      {
        customerId: firebaseUid,
        customerName: 'Rajesh Kumar',
        customerEmail: driverEmail,
        userType: 'driver',
        assignedDriverId: firebaseUid,
        gps: {
          latitude: 12.9716,
          longitude: 77.5946
        },
        timestamp: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString(),
        status: 'Resolved',
        adminNotes: 'Vehicle breakdown resolved. Replacement vehicle provided.',
        resolvedAt: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000 + 2 * 60 * 60 * 1000).toISOString()
      },
      {
        customerId: firebaseUid,
        customerName: 'Rajesh Kumar',
        customerEmail: driverEmail,
        userType: 'driver',
        assignedDriverId: firebaseUid,
        gps: {
          latitude: 12.9352,
          longitude: 77.6245
        },
        timestamp: new Date(Date.now() - 3 * 24 * 60 * 60 * 1000).toISOString(),
        status: 'Resolved',
        adminNotes: 'Medical emergency handled. Driver is safe and back to work.',
        resolvedAt: new Date(Date.now() - 3 * 24 * 60 * 60 * 1000 + 30 * 60 * 1000).toISOString()
      }
    ];
    
    // Add to Firebase Realtime Database
    const database = admin.database();
    for (let i = 0; i < sosHistory.length; i++) {
      const sosRef = database.ref('sos_events').push();
      await sosRef.set(sosHistory[i]);
    }
    console.log('✅ SOS history created');
    
    // 8. Create Vehicle Maintenance Records
    console.log('\n🔧 8. Creating vehicle maintenance records...');
    
    const maintenanceRecords = [
      {
        vehicleId: vehicle._id,
        type: 'routine_service',
        description: 'Regular service - Oil change, filter replacement',
        date: new Date('2024-11-15'),
        cost: 3500,
        nextServiceDue: new Date('2025-02-15'),
        status: 'completed',
        serviceCenter: 'Tata Motors Service Center'
      },
      {
        vehicleId: vehicle._id,
        type: 'repair',
        description: 'Brake pad replacement',
        date: new Date('2024-10-20'),
        cost: 2800,
        status: 'completed',
        serviceCenter: 'City Auto Garage'
      }
    ];
    
    await db.collection('maintenance_records').insertMany(maintenanceRecords);
    console.log('✅ Maintenance records created');
    
    console.log('\n========== DEMO DATA CREATION COMPLETE ==========');
    console.log('✅ Driver Email:', driverEmail);
    console.log('✅ Driver Password: Driver123!');
    console.log('✅ Customer Email:', customerEmail);
    console.log('✅ Customer Password: Customer123!');
    console.log('✅ Vehicle: KA01AB1234 (Maruti Eeco - 4 seater)');
    console.log('✅ Active Trip: In Progress');
    console.log('✅ Route: 3 customers assigned (driver + 3 = 4 total capacity)');
    console.log('✅ Stats: 15 completed trips this month');
    console.log('✅ SOS History: 2 resolved alerts');
    console.log('================================================\n');
    
    return {
      success: true,
      driverEmail,
      customerEmail,
      vehicleNumber: 'KA01AB1234',
      tripId: tripResult.insertedId
    };
    
  } catch (error) {
    console.error('\n❌ ========== DEMO DATA CREATION FAILED ==========');
    console.error('Error:', error.message);
    console.error('Stack trace:', error.stack);
    console.error('=================================================\n');
    throw error;
  } finally {
    await client.close();
    console.log('✅ MongoDB connection closed');
    if (admin.apps.length > 0) {
      await admin.app().delete();
      console.log('✅ Firebase connection closed');
    }
  }
}

// Run the demo data creation
if (require.main === module) {
  createDriverTestDemoData()
    .then((result) => {
      console.log('✅ Demo data creation completed successfully');
      console.log('Result:', result);
      process.exit(0);
    })
    .catch((error) => {
      console.error('❌ Demo data creation failed:', error);
      process.exit(1);
    });
}

module.exports = { createDriverTestDemoData };