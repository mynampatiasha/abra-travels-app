// Check ALL Infosys data in both Firebase and MongoDB to understand the full picture
const { MongoClient } = require('mongodb');
const admin = require('firebase-admin');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';

async function checkAllInfosysData() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB Atlas');
    
    const db = client.db('abra_fleet');
    
    console.log('\n' + '='.repeat(80));
    console.log('COMPLETE INFOSYS DATA CHECK');
    console.log('='.repeat(80));
    
    // 1. Check MongoDB rosters collection
    console.log('\n📊 1. MONGODB ROSTERS COLLECTION (Current State):\n');
    
    const mongoRosters = await db.collection('rosters')
      .find({ customerEmail: { $regex: '@infosys\\.com', $options: 'i' } })
      .toArray();
    
    console.log(`   Found: ${mongoRosters.length} rosters\n`);
    
    if (mongoRosters.length > 0) {
      mongoRosters.forEach((r, i) => {
        console.log(`   ${i + 1}. ${r.customerName} (${r.customerEmail})`);
        console.log(`      Vehicle: ${r.vehicleNumber || 'NONE'}`);
        console.log(`      Driver: ${r.driverName || 'NONE'}`);
        console.log(`      Status: ${r.status}`);
        console.log('');
      });
    } else {
      console.log('   ❌ NO ROSTERS FOUND (All were deleted)\n');
    }
    
    // 2. Check MongoDB users collection
    console.log('\n📊 2. MONGODB USERS COLLECTION (Infosys Customers):\n');
    
    const mongoUsers = await db.collection('users')
      .find({ 
        email: { $regex: '@infosys\\.com', $options: 'i' },
        role: 'customer'
      })
      .toArray();
    
    console.log(`   Found: ${mongoUsers.length} Infosys customers\n`);
    
    mongoUsers.forEach((u, i) => {
      console.log(`   ${i + 1}. ${u.name} (${u.email})`);
      console.log(`      UID: ${u.uid || u._id}`);
      console.log(`      Phone: ${u.phone || 'N/A'}`);
      console.log('');
    });
    
    // 3. Check Firebase Authentication
    console.log('\n📊 3. FIREBASE AUTHENTICATION (Infosys Users):\n');
    
    try {
      // Initialize Firebase if not already done
      if (!admin.apps.length) {
        const serviceAccount = require('./serviceAccountKey.json');
        admin.initializeApp({
          credential: admin.credential.cert(serviceAccount)
        });
      }
      
      const listUsersResult = await admin.auth().listUsers();
      const infosysFirebaseUsers = listUsersResult.users.filter(u => 
        u.email && u.email.endsWith('@infosys.com')
      );
      
      console.log(`   Found: ${infosysFirebaseUsers.length} Infosys users in Firebase Auth\n`);
      
      infosysFirebaseUsers.forEach((u, i) => {
        console.log(`   ${i + 1}. ${u.displayName || 'N/A'} (${u.email})`);
        console.log(`      UID: ${u.uid}`);
        console.log('');
      });
    } catch (firebaseError) {
      console.log('   ⚠️  Could not check Firebase (credentials issue)');
      console.log(`   Error: ${firebaseError.message}\n`);
    }
    
    // 4. Check vehicles for Infosys organization
    console.log('\n📊 4. VEHICLES FOR INFOSYS ORGANIZATION:\n');
    
    const infosysVehicles = await db.collection('vehicles')
      .find({ organization: '@infosys.com' })
      .toArray();
    
    console.log(`   Found: ${infosysVehicles.length} vehicles\n`);
    
    if (infosysVehicles.length > 0) {
      infosysVehicles.forEach((v, i) => {
        console.log(`   ${i + 1}. ${v.vehicleNumber}`);
        console.log(`      Driver: ${v.driverId || 'NONE'}`);
        console.log(`      Capacity: ${v.capacity || 'N/A'}`);
        console.log(`      Organization: ${v.organization}`);
        console.log('');
      });
    } else {
      console.log('   ❌ NO VEHICLES assigned to Infosys organization\n');
    }
    
    // 5. Check drivers for Infosys organization
    console.log('\n📊 5. DRIVERS FOR INFOSYS ORGANIZATION:\n');
    
    const infosysDrivers = await db.collection('drivers')
      .find({ organization: '@infosys.com' })
      .toArray();
    
    console.log(`   Found: ${infosysDrivers.length} drivers\n`);
    
    if (infosysDrivers.length > 0) {
      infosysDrivers.forEach((d, i) => {
        console.log(`   ${i + 1}. ${d.name} (${d.driverId})`);
        console.log(`      Phone: ${d.phone || 'N/A'}`);
        console.log(`      Organization: ${d.organization}`);
        console.log('');
      });
    } else {
      console.log('   ❌ NO DRIVERS assigned to Infosys organization\n');
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('SUMMARY & ANALYSIS');
    console.log('='.repeat(80));
    
    console.log('\n🔍 WHAT HAPPENED:');
    console.log(`   • ${mongoUsers.length} Infosys customers exist in the system`);
    console.log(`   • ${mongoRosters.length} rosters currently in database (${mongoRosters.length === 0 ? 'ALL DELETED' : 'some remain'})`);
    console.log(`   • ${infosysVehicles.length} vehicles assigned to Infosys`);
    console.log(`   • ${infosysDrivers.length} drivers assigned to Infosys`);
    
    console.log('\n💡 THE LOGIC:');
    console.log('   Without vehicles and drivers assigned to the organization,');
    console.log('   roster assignments CANNOT happen automatically.');
    console.log('   You need to:');
    console.log('   1. Assign vehicles to @infosys.com organization');
    console.log('   2. Assign drivers to those vehicles');
    console.log('   3. THEN use bulk import or manual assignment');
    
    console.log('\n📝 NEXT STEPS:');
    if (mongoRosters.length === 0) {
      console.log('   ✅ All rosters deleted (as you requested for 2, but script deleted all 5)');
      console.log('   ❌ Need to restore the 3 that should NOT have been deleted:');
      console.log('      - Rajesh Kumar');
      console.log('      - Priya Sharma');
      console.log('      - Amit Patel');
      console.log('   ⚠️  BUT: We need to know which vehicle/driver they were assigned to!');
    }
    
    console.log('\n');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await client.close();
  }
}

checkAllInfosysData();
