// create-rajesh-kumar-comprehensive-demo-data.js
// Creates comprehensive demo data for rajesh.kumar@abrafleet.com for demonstration

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

async function createRajeshKumarComprehensiveDemoData() {
  console.log('\n🚗 ========== CREATING RAJESH KUMAR COMPREHENSIVE DEMO DATA ==========\n');
  
  const client = new MongoClient(MONGO_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db(DB_NAME);
    
    const driverEmail = 'rajesh.kumar@abrafleet.com';
    const driverId = 'DRV-100001';
    
    console.log('🔍 Setting up comprehensive demo data for:', driverEmail);
    
    // 1. Ensure Driver Profile Exists with Complete Data
    console.log('\n📝 1. Creating/updating comprehensive driver profile...');
    
    // Get or create Firebase UID
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
        password: 'Rajesh123!',
        displayName: 'Rajesh Kumar',
        disabled: false
      });
      firebaseUid = firebaseUser.uid;
      
      // Set custom claims
      await admin.auth().setCustomUserClaims(firebaseUid, {
        role: 'driver',
        driverId: driverId
      });
      
      console.log('✅ Created Firebase user:', firebaseUid);
    }
    
    const comprehensiveDriverData = {
      driverId: driverId,
      uid: firebaseUid,
      firebaseUid: firebaseUid,
      name: 'Rajesh Kumar',
      email: driverEmail,
      phone: '+91-9876543270',
      personalInfo: {
        firstName: 'Rajesh',
        lastName: 'Kumar',
        email: driverEmail,
        phone: '+91-9876543270',
        dateOfBirth: new Date('1987-11-25'),
        bloodGroup: 'O-',
        gender: 'Male',
        address: {
          street: '654 Park Street',
          city: 'Kolkata',
          state: 'West Bengal',
          postalCode: '700001',
          country: 'India'
        }
      },
      license: {
        licenseNumber: 'WB0520230007890',
        type: 'LMV',
        issueDate: new Date('2020-06-12'),
        expiryDate: new Date('2030-06-11'),
        issuingAuthority: 'RTO Kolkata'
      },
      emergencyContact: {
        name: 'Meera Kumar',
        relationship: 'Spouse',
        phone: '+91-9876543219'
      },
      address: {
        street: '654 Park Street',
        city: 'Kolkata',
        state: 'West Bengal',
        postalCode: '700001',
        country: 'India'
      },
      employment: {
        joinDate: new Date('2024-02-15'),
        employmentType: 'Full-time',
        salary: 46000,
        employeeId: 'EMP007'
      },
      bankDetails: {
        bankName: 'PNB Bank',
        accountHolderName: 'Rajesh Kumar',
        accountNumber: '56789012345678',
        ifscCode: 'PUNB0005678'
      },
      documents: [
        {
          id: new ObjectId().toString(),
          documentType: 'driving_license',
          documentName: 'Driving License',
          documentUrl: '/documents/rajesh_license.pdf',
          expiryDate: new Date('2030-06-11'),
          uploadedAt: new Date('2024-02-15'),
          uploadedBy: 'admin',
          status: 'verified'
        },
        {
          id: new ObjectId().toString(),
          documentType: 'aadhar',
          documentName: 'Aadhar Card',
          documentUrl: '/documents/rajesh_aadhar.pdf',
          uploadedAt: new Date('2024-02-15'),
          uploadedBy: 'admin',
          status: 'verified'
        },
        {
          id: new ObjectId().toString(),
          documentType: 'pan',
          documentName: 'PAN Card',
          documentUrl: '/documents/rajesh_pan.pdf',
          uploadedAt: new Date('2024-02-15'),
          uploadedBy: 'admin',
          status: 'verified'
        },
        {
          id: new ObjectId().toString(),
          documentType: 'medical_certificate',
          documentName: 'Medical Fitness Certificate',
          documentUrl: '/documents/rajesh_medical.pdf',
          expiryDate: new Date('2025-02-15'),
          uploadedAt: new Date('2024-02-15'),
          uploadedBy: 'admin',
          status: 'verified'
        }
      ],
      assignedVehicle: 'KA02CD5678',
      status: 'active',
      rating: 4.7,
      totalTrips: 0, // Will be updated after trip creation
      joinedDate: new Date('2024-02-15'),
      createdAt: new Date('2024-02-15'),
      updatedAt: new Date()
    };
    
    await db.collection('drivers').replaceOne(
      { driverId: driverId },
      comprehensiveDriverData,
      { upsert: true }
    );
    console.log('✅ Comprehensive driver profile created/updated');
    
    // Ensure admin_users entry exists
    await db.collection('admin_users').replaceOne(
      { email: driverEmail },
      {
        firebaseUid: firebaseUid,
        email: driverEmail,
        name: 'Rajesh Kumar',
        role: 'driver',
        phone: '+91-9876543270',
        status: 'active',
        driverId: driverId,
        modules: [],
        permissions: {},
        createdAt: new Date('2024-02-15'),
        updatedAt: new Date(),
        lastActive: new Date()
      },
      { upsert: true }
    );
    console.log('✅ Admin users entry created/updated');
    
    // 2. Create/Update Assigned Vehicle
    console.log('\n🚙 2. Creating assigned vehicle...');
    const vehicleData = {
      vehicleId: 'VH-RAJ-001',
      registrationNumber: 'KA02CD5678',
      make: 'Tata',
      model: 'Ace Gold',
      year: 2023,
      type: 'Mini Truck',
      fuelType: 'Diesel',
      capacity: 4,
      color: 'White',
      chassisNumber: 'TATA123456789RAJ',
      engineNumber: 'ENG987654321RAJ',
      insurance: {
        policyNumber: 'INS789456123RAJ',
        provider: 'ICICI Lombard',
        expiryDate: new Date('2025-08-15'),
        status: 'active'
      },
      fitness: {
        certificateNumber: 'FIT789456RAJ',
        expiryDate: new Date('2025-05-20'),
        status: 'valid'
      },
      pollution: {
        certificateNumber: 'PUC789456RAJ',
        expiryDate: new Date('2024-12-30'),
        status: 'valid'
      },
      assignedDriver: driverId,
      assignedDriverName: 'Rajesh Kumar',
      status: 'active',
      organizationId: 'ORG-001',
      organizationName: 'ABRA Fleet Management',
      vendor: 'Tata Motors',
      purchaseDate: new Date('2023-01-15'),
      currentMileage: 28450,
      lastServiceDate: new Date('2024-11-20'),
      nextServiceDue: new Date('2025-02-20'),
      fuelEfficiency: 18.5, // km/l
      createdAt: new Date('2023-01-15'),
      updatedAt: new Date()
    };
    
    await db.collection('vehicles').replaceOne(
      { registrationNumber: 'KA02CD5678' },
      vehicleData,
      { upsert: true }
    );
    console.log('✅ Assigned vehicle created/updated');
    
    // 3. Create Demo Customers for Trips
    console.log('\n👥 3. Creating demo customers...');
    const demoCustomers = [
      {
        _id: new ObjectId(),
        uid: 'customer_001_uid',
        email: 'priya.sharma@abrafleet.com',
        name: 'Priya Sharma',
        phone: '+91-9876543280',
        organization: 'ABRA Fleet Management',
        organizationId: 'ORG-001',
        employeeId: 'EMP008',
        department: 'Driver Management',
        designation: 'Driver Supervisor',
        addresses: {
          home: {
            address: 'Marathahalli Bridge, Bangalore',
            latitude: 12.9591,
            longitude: 77.6974,
            type: 'home'
          },
          office: {
            address: 'Abra Fleet Head Office, Bangalore',
            latitude: 12.9716,
            longitude: 77.5946,
            type: 'office'
          }
        },
        currentAddress: 'home',
        status: 'active',
        joinedDate: new Date('2024-01-10'),
        createdAt: new Date('2024-01-10'),
        updatedAt: new Date()
      },
      {
        _id: new ObjectId(),
        uid: 'customer_002_uid',
        email: 'anita.desai@abrafleet.com',
        name: 'Anita Desai',
        phone: '+91-9876543290',
        organization: 'ABRA Fleet Management',
        organizationId: 'ORG-001',
        employeeId: 'EMP009',
        department: 'Route Planning',
        designation: 'Route Planner',
        addresses: {
          home: {
            address: 'Silk Board Junction, Bangalore',
            latitude: 12.9165,
            longitude: 77.6219,
            type: 'home'
          },
          office: {
            address: 'Abra Fleet Head Office, Bangalore',
            latitude: 12.9716,
            longitude: 77.5946,
            type: 'office'
          }
        },
        currentAddress: 'home',
        status: 'active',
        joinedDate: new Date('2024-01-15'),
        createdAt: new Date('2024-01-15'),
        updatedAt: new Date()
      },
      {
        _id: new ObjectId(),
        uid: 'customer_003_uid',
        email: 'robert.wilson@abrafleet.com',
        name: 'Robert Wilson',
        phone: '+91-9876543250',
        organization: 'ABRA Fleet Management',
        organizationId: 'ORG-001',
        employeeId: 'EMP005',
        department: 'Marketing',
        designation: 'Marketing Specialist',
        addresses: {
          home: {
            address: 'Indiranagar 100 Feet Road, Bangalore',
            latitude: 12.9784,
            longitude: 77.6408,
            type: 'home'
          },
          office: {
            address: 'Abra Fleet Head Office, Bangalore',
            latitude: 12.9716,
            longitude: 77.5946,
            type: 'office'
          }
        },
        currentAddress: 'home',
        status: 'active',
        joinedDate: new Date('2024-01-05'),
        createdAt: new Date('2024-01-05'),
        updatedAt: new Date()
      },
      {
        _id: new ObjectId(),
        uid: 'customer_004_uid',
        email: 'jennifer.garcia@abrafleet.com',
        name: 'Jennifer Garcia',
        phone: '+91-9876543260',
        organization: 'ABRA Fleet Management',
        organizationId: 'ORG-001',
        employeeId: 'EMP006',
        department: 'Customer Support',
        designation: 'Support Lead',
        addresses: {
          home: {
            address: 'Whitefield Main Road, Bangalore',
            latitude: 12.9698,
            longitude: 77.7500,
            type: 'home'
          },
          office: {
            address: 'Abra Fleet Head Office, Bangalore',
            latitude: 12.9716,
            longitude: 77.5946,
            type: 'office'
          }
        },
        currentAddress: 'home',
        status: 'active',
        joinedDate: new Date('2024-01-08'),
        createdAt: new Date('2024-01-08'),
        updatedAt: new Date()
      }
    ];
    
    // Insert customers
    for (const customer of demoCustomers) {
      await db.collection('users').replaceOne(
        { email: customer.email },
        customer,
        { upsert: true }
      );
    }
    console.log(`✅ Created ${demoCustomers.length} demo customers`);
    
    // 4. Create Comprehensive Trip History (Last 60 Days)
    console.log('\n🚗 4. Creating comprehensive trip history...');
    
    const trips = [];
    const now = new Date();
    const customers = demoCustomers;
    
    // Generate 45 trips over the last 60 days
    for (let i = 0; i < 45; i++) {
      const daysAgo = Math.floor(Math.random() * 60) + 1;
      const tripDate = new Date(now);
      tripDate.setDate(tripDate.getDate() - daysAgo);
      
      // Random start time between 7 AM and 6 PM
      const startHour = 7 + Math.floor(Math.random() * 11);
      const startMinute = Math.floor(Math.random() * 60);
      
      const startTime = new Date(tripDate);
      startTime.setHours(startHour, startMinute, 0, 0);
      
      // Trip duration between 25-75 minutes
      const durationMinutes = 25 + Math.floor(Math.random() * 50);
      const endTime = new Date(startTime);
      endTime.setMinutes(endTime.getMinutes() + durationMinutes);
      
      // Random customer
      const randomCustomer = customers[Math.floor(Math.random() * customers.length)];
      
      // Random distance between 8-45 km
      const distance = 8 + Math.random() * 37;
      
      // Random rating between 4.2-5.0 for completed trips
      const rating = 4.2 + Math.random() * 0.8;
      
      // 92% completed, 5% cancelled, 3% in_progress (only for recent trips)
      let status = 'completed';
      if (Math.random() < 0.05) {
        status = 'cancelled';
      } else if (Math.random() < 0.03 && daysAgo <= 1) {
        status = 'in_progress';
      }
      
      // Calculate fare based on distance and time
      const baseFare = 80;
      const perKmRate = 15;
      const timeRate = 2; // per minute
      const totalFare = baseFare + (distance * perKmRate) + (durationMinutes * timeRate);
      
      const trip = {
        _id: new ObjectId(),
        tripId: `TRIP-RAJ-${Date.now()}-${i}`,
        tripNumber: `TR-2024-${String(2000 + i).padStart(4, '0')}`,
        driverId: driverId,
        driverName: 'Rajesh Kumar',
        driverFirebaseUid: firebaseUid,
        customerId: randomCustomer._id,
        customerName: randomCustomer.name,
        customerEmail: randomCustomer.email,
        customerPhone: randomCustomer.phone,
        vehicleId: 'VH-RAJ-001',
        vehicleNumber: 'KA02CD5678',
        pickupLocation: {
          address: randomCustomer.addresses.home.address,
          coordinates: {
            latitude: randomCustomer.addresses.home.latitude,
            longitude: randomCustomer.addresses.home.longitude
          },
          type: 'home'
        },
        dropLocation: {
          address: randomCustomer.addresses.office.address,
          coordinates: {
            latitude: randomCustomer.addresses.office.latitude,
            longitude: randomCustomer.addresses.office.longitude
          },
          type: 'office'
        },
        startTime: startTime,
        endTime: status === 'in_progress' ? null : endTime,
        scheduledStartTime: new Date(startTime.getTime() - 10 * 60 * 1000), // 10 minutes before actual
        scheduledEndTime: status === 'in_progress' ? null : new Date(endTime.getTime() + 5 * 60 * 1000), // 5 minutes after actual
        actualStartTime: startTime,
        actualEndTime: status === 'in_progress' ? null : endTime,
        status: status,
        distance: parseFloat(distance.toFixed(2)),
        rating: status === 'completed' ? parseFloat(rating.toFixed(1)) : null,
        fare: {
          baseFare: baseFare,
          distanceFare: parseFloat((distance * perKmRate).toFixed(2)),
          timeFare: parseFloat((durationMinutes * timeRate).toFixed(2)),
          totalFare: parseFloat(totalFare.toFixed(2)),
          currency: 'INR'
        },
        fuelConsumed: parseFloat((distance / 18.5).toFixed(2)), // Based on vehicle efficiency
        route: {
          totalDistance: parseFloat(distance.toFixed(2)),
          estimatedDuration: durationMinutes,
          actualDuration: status === 'completed' ? durationMinutes : null,
          waypoints: [
            {
              latitude: randomCustomer.addresses.home.latitude,
              longitude: randomCustomer.addresses.home.longitude,
              address: randomCustomer.addresses.home.address,
              sequence: 1
            },
            {
              latitude: randomCustomer.addresses.office.latitude,
              longitude: randomCustomer.addresses.office.longitude,
              address: randomCustomer.addresses.office.address,
              sequence: 2
            }
          ]
        },
        organizationId: 'ORG-001',
        organizationName: 'ABRA Fleet Management',
        tripType: Math.random() > 0.8 ? 'emergency' : 'scheduled',
        paymentStatus: status === 'completed' ? 'paid' : 'pending',
        createdAt: new Date(startTime.getTime() - 2 * 60 * 60 * 1000), // Created 2 hours before trip
        updatedAt: status === 'in_progress' ? new Date() : endTime,
        metadata: {
          source: 'comprehensive_demo_system',
          createdBy: 'demo_script',
          version: '2.0',
          weather: ['sunny', 'cloudy', 'rainy'][Math.floor(Math.random() * 3)],
          trafficCondition: ['light', 'moderate', 'heavy'][Math.floor(Math.random() * 3)]
        }
      };
      
      trips.push(trip);
    }
    
    // Sort trips by start time (newest first)
    trips.sort((a, b) => b.startTime - a.startTime);
    
    console.log(`🚀 Creating ${trips.length} comprehensive trips for Rajesh Kumar...`);
    
    // Delete existing trips for Rajesh Kumar to avoid duplicates
    const deleteResult = await db.collection('trips').deleteMany({
      driverId: driverId
    });
    console.log(`🗑️  Deleted ${deleteResult.deletedCount} existing trips`);
    
    // Insert new trips
    const insertResult = await db.collection('trips').insertMany(trips);
    console.log(`✅ Inserted ${insertResult.insertedCount} new comprehensive trips`);
    
    // 5. Create Active Rosters for Current Week
    console.log('\n📋 5. Creating active rosters for current week...');
    
    const rosters = [];
    const today = new Date();
    
    // Create rosters for next 7 days
    for (let dayOffset = 0; dayOffset < 7; dayOffset++) {
      const rosterDate = new Date(today);
      rosterDate.setDate(today.getDate() + dayOffset);
      
      // Skip weekends for office trips
      if (rosterDate.getDay() === 0 || rosterDate.getDay() === 6) continue;
      
      // Morning shift roster
      const morningRoster = {
        _id: new ObjectId(),
        rosterId: `RST-RAJ-${rosterDate.getFullYear()}-${String(rosterDate.getMonth() + 1).padStart(2, '0')}-${String(rosterDate.getDate()).padStart(2, '0')}-AM`,
        driverId: driverId,
        driverName: 'Rajesh Kumar',
        vehicleId: 'VH-RAJ-001',
        vehicleNumber: 'KA02CD5678',
        date: rosterDate.toISOString().split('T')[0],
        shift: 'morning',
        shiftTime: '08:30 - 10:30',
        route: {
          routeName: 'Morning Office Route',
          startLocation: {
            address: 'Fleet Depot, Electronic City, Bangalore',
            latitude: 12.8456,
            longitude: 77.6603
          },
          endLocation: {
            address: 'Abra Fleet Head Office, Bangalore',
            latitude: 12.9716,
            longitude: 77.5946
          },
          totalDistance: 28.5,
          estimatedDuration: 90
        },
        customers: customers.slice(0, 3).map((customer, index) => ({
          customerId: customer._id,
          customerName: customer.name,
          customerEmail: customer.email,
          customerPhone: customer.phone,
          pickupLocation: customer.addresses.home.address,
          dropLocation: customer.addresses.office.address,
          pickupTime: `${8 + index * 0.5}:${30 + (index * 15) % 60}`,
          sequence: index + 1,
          status: dayOffset === 0 ? 'picked_up' : 'scheduled'
        })),
        status: dayOffset === 0 ? 'active' : 'scheduled',
        startTime: new Date(rosterDate.setHours(8, 30, 0, 0)),
        endTime: new Date(rosterDate.setHours(10, 30, 0, 0)),
        organizationId: 'ORG-001',
        organizationName: 'ABRA Fleet Management',
        createdAt: new Date(rosterDate.getTime() - 24 * 60 * 60 * 1000),
        updatedAt: new Date()
      };
      
      // Evening shift roster
      const eveningRoster = {
        _id: new ObjectId(),
        rosterId: `RST-RAJ-${rosterDate.getFullYear()}-${String(rosterDate.getMonth() + 1).padStart(2, '0')}-${String(rosterDate.getDate()).padStart(2, '0')}-PM`,
        driverId: driverId,
        driverName: 'Rajesh Kumar',
        vehicleId: 'VH-RAJ-001',
        vehicleNumber: 'KA02CD5678',
        date: rosterDate.toISOString().split('T')[0],
        shift: 'evening',
        shiftTime: '18:00 - 20:00',
        route: {
          routeName: 'Evening Home Route',
          startLocation: {
            address: 'Abra Fleet Head Office, Bangalore',
            latitude: 12.9716,
            longitude: 77.5946
          },
          endLocation: {
            address: 'Fleet Depot, Electronic City, Bangalore',
            latitude: 12.8456,
            longitude: 77.6603
          },
          totalDistance: 32.8,
          estimatedDuration: 95
        },
        customers: customers.slice(0, 3).map((customer, index) => ({
          customerId: customer._id,
          customerName: customer.name,
          customerEmail: customer.email,
          customerPhone: customer.phone,
          pickupLocation: customer.addresses.office.address,
          dropLocation: customer.addresses.home.address,
          pickupTime: `${18 + index * 0.5}:${(index * 15) % 60}`,
          sequence: index + 1,
          status: dayOffset === 0 ? 'scheduled' : 'scheduled'
        })),
        status: dayOffset === 0 ? 'scheduled' : 'scheduled',
        startTime: new Date(rosterDate.setHours(18, 0, 0, 0)),
        endTime: new Date(rosterDate.setHours(20, 0, 0, 0)),
        organizationId: 'ORG-001',
        organizationName: 'ABRA Fleet Management',
        createdAt: new Date(rosterDate.getTime() - 24 * 60 * 60 * 1000),
        updatedAt: new Date()
      };
      
      rosters.push(morningRoster, eveningRoster);
    }
    
    // Delete existing rosters for Rajesh Kumar
    await db.collection('rosters').deleteMany({ driverId: driverId });
    
    // Insert new rosters
    const rosterInsertResult = await db.collection('rosters').insertMany(rosters);
    console.log(`✅ Created ${rosterInsertResult.insertedCount} rosters for the week`);
    
    // 6. Create Driver Performance Analytics
    console.log('\n📊 6. Creating driver performance analytics...');
    
    const completedTrips = trips.filter(t => t.status === 'completed');
    const totalDistance = completedTrips.reduce((sum, t) => sum + t.distance, 0);
    const avgRating = completedTrips.reduce((sum, t) => sum + (t.rating || 0), 0) / completedTrips.length;
    const totalWorkingHours = completedTrips.reduce((sum, t) => {
      if (t.startTime && t.endTime) {
        return sum + (t.endTime - t.startTime) / (1000 * 60 * 60);
      }
      return sum;
    }, 0);
    const totalFuelConsumed = completedTrips.reduce((sum, t) => sum + (t.fuelConsumed || 0), 0);
    const totalEarnings = completedTrips.reduce((sum, t) => sum + (t.fare?.totalFare || 0), 0);
    
    // Monthly performance data for last 3 months
    const performanceData = [];
    for (let monthOffset = 0; monthOffset < 3; monthOffset++) {
      const performanceDate = new Date(now);
      performanceDate.setMonth(now.getMonth() - monthOffset);
      
      const monthTrips = completedTrips.filter(trip => {
        const tripDate = new Date(trip.startTime);
        return tripDate.getMonth() === performanceDate.getMonth() && 
               tripDate.getFullYear() === performanceDate.getFullYear();
      });
      
      const monthDistance = monthTrips.reduce((sum, t) => sum + t.distance, 0);
      const monthHours = monthTrips.reduce((sum, t) => {
        if (t.startTime && t.endTime) {
          return sum + (t.endTime - t.startTime) / (1000 * 60 * 60);
        }
        return sum;
      }, 0);
      const monthEarnings = monthTrips.reduce((sum, t) => sum + (t.fare?.totalFare || 0), 0);
      const monthRating = monthTrips.length > 0 ? 
        monthTrips.reduce((sum, t) => sum + (t.rating || 0), 0) / monthTrips.length : 0;
      
      performanceData.push({
        _id: new ObjectId(),
        driverId: driverId,
        driverFirebaseUid: firebaseUid,
        month: performanceDate.getMonth() + 1,
        year: performanceDate.getFullYear(),
        totalTrips: monthTrips.length,
        completedTrips: monthTrips.length,
        cancelledTrips: trips.filter(t => {
          const tripDate = new Date(t.startTime);
          return t.status === 'cancelled' && 
                 tripDate.getMonth() === performanceDate.getMonth() && 
                 tripDate.getFullYear() === performanceDate.getFullYear();
        }).length,
        totalDistance: parseFloat(monthDistance.toFixed(2)),
        totalWorkingHours: parseFloat(monthHours.toFixed(2)),
        avgRating: parseFloat(monthRating.toFixed(2)),
        totalFuelConsumed: parseFloat((monthDistance / 18.5).toFixed(2)),
        totalEarnings: parseFloat(monthEarnings.toFixed(2)),
        onTimeTrips: Math.floor(monthTrips.length * 0.92), // 92% on-time rate
        efficiency: parseFloat(((monthDistance / monthHours) || 0).toFixed(2)),
        createdAt: new Date(),
        updatedAt: new Date()
      });
    }
    
    // Insert performance data
    await db.collection('driver_performance').deleteMany({ driverId: driverId });
    await db.collection('driver_performance').insertMany(performanceData);
    console.log(`✅ Created performance analytics for ${performanceData.length} months`);
    
    // 7. Create Notifications for Driver
    console.log('\n🔔 7. Creating driver notifications...');
    
    const notifications = [
      {
        _id: new ObjectId(),
        userId: firebaseUid,
        userType: 'driver',
        title: 'Welcome to ABRA Fleet!',
        message: 'Welcome aboard, Rajesh! Your driver profile has been activated. Start your journey with us today.',
        type: 'welcome',
        priority: 'high',
        category: 'system',
        isRead: false,
        createdAt: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000),
        updatedAt: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000)
      },
      {
        _id: new ObjectId(),
        userId: firebaseUid,
        userType: 'driver',
        title: 'Vehicle Assigned',
        message: 'Vehicle KA02CD5678 (Tata Ace Gold) has been assigned to you. Please inspect the vehicle before starting your trips.',
        type: 'vehicle_assignment',
        priority: 'high',
        category: 'vehicle',
        isRead: true,
        createdAt: new Date(Date.now() - 6 * 24 * 60 * 60 * 1000),
        updatedAt: new Date(Date.now() - 5 * 24 * 60 * 60 * 1000)
      },
      {
        _id: new ObjectId(),
        userId: firebaseUid,
        userType: 'driver',
        title: 'New Route Assignment',
        message: 'You have been assigned to the Electronic City - Whitefield route. Check your roster for details.',
        type: 'route_assignment',
        priority: 'medium',
        category: 'route',
        isRead: true,
        createdAt: new Date(Date.now() - 5 * 24 * 60 * 60 * 1000),
        updatedAt: new Date(Date.now() - 4 * 24 * 60 * 60 * 1000)
      },
      {
        _id: new ObjectId(),
        userId: firebaseUid,
        userType: 'driver',
        title: 'Excellent Performance!',
        message: 'Congratulations! You maintained a 4.7-star rating this month. Keep up the great work!',
        type: 'performance',
        priority: 'medium',
        category: 'achievement',
        isRead: false,
        createdAt: new Date(Date.now() - 2 * 24 * 60 * 60 * 1000),
        updatedAt: new Date(Date.now() - 2 * 24 * 60 * 60 * 1000)
      },
      {
        _id: new ObjectId(),
        userId: firebaseUid,
        userType: 'driver',
        title: 'Vehicle Service Reminder',
        message: 'Your vehicle KA02CD5678 is due for service on 2025-02-20. Please schedule the service appointment.',
        type: 'maintenance',
        priority: 'medium',
        category: 'vehicle',
        isRead: false,
        createdAt: new Date(Date.now() - 1 * 24 * 60 * 60 * 1000),
        updatedAt: new Date(Date.now() - 1 * 24 * 60 * 60 * 1000)
      },
      {
        _id: new ObjectId(),
        userId: firebaseUid,
        userType: 'driver',
        title: 'Today\'s Route Ready',
        message: 'Your route for today is ready. You have 3 customers assigned. Safe driving!',
        type: 'daily_route',
        priority: 'high',
        category: 'route',
        isRead: false,
        createdAt: new Date(Date.now() - 2 * 60 * 60 * 1000),
        updatedAt: new Date(Date.now() - 2 * 60 * 60 * 1000)
      }
    ];
    
    await db.collection('notifications').deleteMany({ userId: firebaseUid });
    await db.collection('notifications').insertMany(notifications);
    console.log(`✅ Created ${notifications.length} driver notifications`);
    
    // 8. Create Vehicle Maintenance Records
    console.log('\n🔧 8. Creating vehicle maintenance records...');
    
    const maintenanceRecords = [
      {
        _id: new ObjectId(),
        vehicleId: 'VH-RAJ-001',
        vehicleNumber: 'KA02CD5678',
        driverId: driverId,
        type: 'routine_service',
        description: 'Regular service - Engine oil change, air filter replacement, brake inspection',
        scheduledDate: new Date('2024-11-20'),
        completedDate: new Date('2024-11-20'),
        cost: 4200,
        serviceCenter: 'Tata Motors Authorized Service Center',
        serviceProvider: 'Tata Motors',
        nextServiceDue: new Date('2025-02-20'),
        mileageAtService: 27800,
        status: 'completed',
        parts: [
          { name: 'Engine Oil', quantity: '4L', cost: 1200 },
          { name: 'Air Filter', quantity: '1', cost: 450 },
          { name: 'Oil Filter', quantity: '1', cost: 350 },
          { name: 'Labor Charges', quantity: '1', cost: 2200 }
        ],
        createdAt: new Date('2024-11-15'),
        updatedAt: new Date('2024-11-20')
      },
      {
        _id: new ObjectId(),
        vehicleId: 'VH-RAJ-001',
        vehicleNumber: 'KA02CD5678',
        driverId: driverId,
        type: 'repair',
        description: 'Front brake pad replacement and brake fluid top-up',
        scheduledDate: new Date('2024-10-15'),
        completedDate: new Date('2024-10-15'),
        cost: 3200,
        serviceCenter: 'City Auto Garage',
        serviceProvider: 'Independent Garage',
        mileageAtService: 26500,
        status: 'completed',
        parts: [
          { name: 'Front Brake Pads', quantity: '1 Set', cost: 1800 },
          { name: 'Brake Fluid', quantity: '500ml', cost: 200 },
          { name: 'Labor Charges', quantity: '1', cost: 1200 }
        ],
        createdAt: new Date('2024-10-10'),
        updatedAt: new Date('2024-10-15')
      },
      {
        _id: new ObjectId(),
        vehicleId: 'VH-RAJ-001',
        vehicleNumber: 'KA02CD5678',
        driverId: driverId,
        type: 'inspection',
        description: 'Monthly vehicle inspection and safety check',
        scheduledDate: new Date('2024-12-15'),
        completedDate: new Date('2024-12-15'),
        cost: 500,
        serviceCenter: 'ABRA Fleet Inspection Center',
        serviceProvider: 'In-house',
        mileageAtService: 28200,
        status: 'completed',
        inspectionResults: {
          engine: 'Good',
          brakes: 'Excellent',
          tires: 'Good',
          lights: 'Excellent',
          safety: 'Passed'
        },
        createdAt: new Date('2024-12-10'),
        updatedAt: new Date('2024-12-15')
      }
    ];
    
    await db.collection('maintenance_records').deleteMany({ driverId: driverId });
    await db.collection('maintenance_records').insertMany(maintenanceRecords);
    console.log(`✅ Created ${maintenanceRecords.length} maintenance records`);
    
    // 9. Update Driver Profile with Calculated Stats
    console.log('\n📈 9. Updating driver profile with calculated stats...');
    
    await db.collection('drivers').updateOne(
      { driverId: driverId },
      {
        $set: {
          totalTrips: trips.length,
          completedTrips: completedTrips.length,
          rating: parseFloat(avgRating.toFixed(1)),
          totalDistance: parseFloat(totalDistance.toFixed(2)),
          totalWorkingHours: parseFloat(totalWorkingHours.toFixed(2)),
          totalEarnings: parseFloat(totalEarnings.toFixed(2)),
          efficiency: parseFloat(((totalDistance / totalWorkingHours) || 0).toFixed(2)),
          onTimePercentage: 92,
          updatedAt: new Date()
        }
      }
    );
    console.log('✅ Driver profile updated with calculated statistics');
    
    // 10. Create Summary Report
    console.log('\n📋 10. Generating comprehensive summary...');
    
    const summary = {
      driverProfile: {
        driverId: driverId,
        name: 'Rajesh Kumar',
        email: driverEmail,
        phone: '+91-9876543270',
        firebaseUid: firebaseUid,
        status: 'active'
      },
      vehicle: {
        vehicleId: 'VH-RAJ-001',
        registrationNumber: 'KA02CD5678',
        make: 'Tata',
        model: 'Ace Gold',
        type: 'Mini Truck',
        capacity: 4
      },
      statistics: {
        totalTrips: trips.length,
        completedTrips: completedTrips.length,
        cancelledTrips: trips.filter(t => t.status === 'cancelled').length,
        inProgressTrips: trips.filter(t => t.status === 'in_progress').length,
        totalDistance: parseFloat(totalDistance.toFixed(1)),
        avgRating: parseFloat(avgRating.toFixed(1)),
        totalWorkingHours: parseFloat(totalWorkingHours.toFixed(1)),
        totalEarnings: parseFloat(totalEarnings.toFixed(2)),
        fuelEfficiency: parseFloat((totalDistance / totalFuelConsumed).toFixed(1))
      },
      rosters: {
        totalRosters: rosters.length,
        activeRosters: rosters.filter(r => r.status === 'active').length,
        scheduledRosters: rosters.filter(r => r.status === 'scheduled').length
      },
      notifications: {
        totalNotifications: notifications.length,
        unreadNotifications: notifications.filter(n => !n.isRead).length
      },
      maintenance: {
        totalRecords: maintenanceRecords.length,
        lastServiceDate: '2024-11-20',
        nextServiceDue: '2025-02-20'
      }
    };
    
    console.log('\n========== COMPREHENSIVE DEMO DATA CREATION COMPLETE ==========');
    console.log('✅ Driver Email:', driverEmail);
    console.log('✅ Driver Password: Rajesh123!');
    console.log('✅ Firebase UID:', firebaseUid);
    console.log('✅ Vehicle: KA02CD5678 (Tata Ace Gold - 4 seater)');
    console.log('✅ Total Trips Created:', trips.length);
    console.log('✅ Completed Trips:', completedTrips.length);
    console.log('✅ Total Distance:', totalDistance.toFixed(1), 'km');
    console.log('✅ Average Rating:', avgRating.toFixed(1), '/5.0');
    console.log('✅ Total Working Hours:', totalWorkingHours.toFixed(1), 'hours');
    console.log('✅ Total Earnings: ₹', totalEarnings.toFixed(2));
    console.log('✅ Active Rosters:', rosters.filter(r => r.status === 'active').length);
    console.log('✅ Scheduled Rosters:', rosters.filter(r => r.status === 'scheduled').length);
    console.log('✅ Unread Notifications:', notifications.filter(n => !n.isRead).length);
    console.log('✅ Maintenance Records:', maintenanceRecords.length);
    console.log('================================================================\n');
    
    return {
      success: true,
      summary,
      message: 'Comprehensive demo data created successfully for rajesh.kumar@abrafleet.com'
    };
    
  } catch (error) {
    console.error('\n❌ ========== COMPREHENSIVE DEMO DATA CREATION FAILED ==========');
    console.error('Error:', error.message);
    console.error('Stack trace:', error.stack);
    console.error('================================================================\n');
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

// Run the comprehensive demo data creation
if (require.main === module) {
  createRajeshKumarComprehensiveDemoData()
    .then((result) => {
      console.log('✅ Comprehensive demo data creation completed successfully');
      console.log('Summary:', JSON.stringify(result.summary, null, 2));
      process.exit(0);
    })
    .catch((error) => {
      console.error('❌ Comprehensive demo data creation failed:', error);
      process.exit(1);
    });
}

module.exports = { createRajeshKumarComprehensiveDemoData };