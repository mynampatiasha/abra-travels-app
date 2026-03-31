// Restore the 3 Infosys rosters that should NOT have been deleted
const { MongoClient, ObjectId } = require('mongodb');
const admin = require('firebase-admin');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';

// Initialize Firebase Admin if not already initialized
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert({
      projectId: process.env.FIREBASE_PROJECT_ID,
      clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
      privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
    }),
  });
}

async function restoreRosters() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB Atlas');
    
    const db = client.db('abra_fleet');
    
    // Get customer UIDs from Firebase
    console.log('\n🔍 Getting customer UIDs from Firebase...\n');
    
    const rajeshUser = await admin.auth().getUserByEmail('rajesh.kumar@infosys.com');
    const priyaUser = await admin.auth().getUserByEmail('priya.sharma@infosys.com');
    const amitUser = await admin.auth().getUserByEmail('amit.patel@infosys.com');
    
    console.log(`✅ Rajesh Kumar UID: ${rajeshUser.uid}`);
    console.log(`✅ Priya Sharma UID: ${priyaUser.uid}`);
    console.log(`✅ Amit Patel UID: ${amitUser.uid}`);
    
    // Get vehicle and driver details for KA01AB1240
    console.log('\n🔍 Getting vehicle KA01AB1240 details...\n');
    
    const vehicle = await db.collection('vehicles').findOne({ vehicleNumber: 'KA01AB1240' });
    
    if (!vehicle) {
      console.log('❌ Vehicle KA01AB1240 not found!');
      return;
    }
    
    console.log(`✅ Vehicle found: ${vehicle.vehicleNumber}`);
    console.log(`   Driver ID: ${vehicle.driverId || 'N/A'}`);
    console.log(`   Capacity: ${vehicle.capacity || 'N/A'}`);
    
    // Get driver details if assigned
    let driverName = null;
    let driverPhone = null;
    
    if (vehicle.driverId) {
      const driver = await db.collection('drivers').findOne({ driverId: vehicle.driverId });
      if (driver) {
        driverName = driver.name;
        driverPhone = driver.phone;
        console.log(`✅ Driver found: ${driverName} (${driverPhone})`);
      }
    }
    
    // Create roster data for the 3 customers
    const rostersToRestore = [
      {
        customerUid: rajeshUser.uid,
        customerName: 'Rajesh Kumar',
        customerEmail: 'rajesh.kumar@infosys.com',
        customerPhone: '+91 9876543210',
        pickupLocation: 'Electronic City, Bangalore',
        pickupLatitude: 12.8456,
        pickupLongitude: 77.6603,
      },
      {
        customerUid: priyaUser.uid,
        customerName: 'Priya Sharma',
        customerEmail: 'priya.sharma@infosys.com',
        customerPhone: '+91 9876543211',
        pickupLocation: 'Whitefield, Bangalore',
        pickupLatitude: 12.9698,
        pickupLongitude: 77.7500,
      },
      {
        customerUid: amitUser.uid,
        customerName: 'Amit Patel',
        customerEmail: 'amit.patel@infosys.com',
        customerPhone: '+91 9876543212',
        pickupLocation: 'Koramangala, Bangalore',
        pickupLatitude: 12.9352,
        pickupLongitude: 77.6245,
      },
    ];
    
    console.log('\n📝 Restoring 3 rosters...\n');
    
    const now = new Date();
    const tomorrow = new Date(now);
    tomorrow.setDate(tomorrow.getDate() + 1);
    tomorrow.setHours(8, 0, 0, 0); // 8 AM tomorrow
    
    for (const rosterData of rostersToRestore) {
      const roster = {
        customerUid: rosterData.customerUid,
        customerName: rosterData.customerName,
        customerEmail: rosterData.customerEmail,
        customerPhone: rosterData.customerPhone,
        pickupLocation: rosterData.pickupLocation,
        pickupLatitude: rosterData.pickupLatitude,
        pickupLongitude: rosterData.pickupLongitude,
        dropLocation: 'Infosys Campus, Electronic City',
        dropLatitude: 12.8456,
        dropLongitude: 77.6603,
        vehicleNumber: vehicle.vehicleNumber,
        vehicleId: vehicle._id.toString(),
        driverId: vehicle.driverId || null,
        driverName: driverName,
        driverPhone: driverPhone,
        tripDate: tomorrow,
        pickupTime: '08:00',
        shift: 'morning',
        status: 'assigned',
        tripType: 'pickup',
        createdAt: now,
        updatedAt: now,
      };
      
      const result = await db.collection('rosters').insertOne(roster);
      console.log(`✅ Restored: ${rosterData.customerName} - ID: ${result.insertedId}`);
    }
    
    console.log('\n✅ Successfully restored 3 rosters!');
    console.log('\n📝 Summary:');
    console.log('   ✅ Rajesh Kumar - Restored with Vehicle KA01AB1240');
    console.log('   ✅ Priya Sharma - Restored with Vehicle KA01AB1240');
    console.log('   ✅ Amit Patel - Restored with Vehicle KA01AB1240');
    console.log('   ❌ Neha Gupta - Correctly deleted (no vehicle)');
    console.log('   ❌ Vikram Singh - Correctly deleted (no vehicle)');
    console.log('\n📱 Next Steps:');
    console.log('   1. Refresh the Client Roster Management page');
    console.log('   2. You should see 3 Infosys rosters in Active Rosters');
    console.log('   3. Neha Gupta and Vikram Singh can now be reassigned via bulk import\n');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error(error);
  } finally {
    await client.close();
  }
}

restoreRosters();
