// scripts/migrate-drivers.js
// Run this ONCE to migrate all existing drivers to admin_users collection

const { MongoClient } = require('mongodb');
const admin = require('firebase-admin');

// Initialize Firebase Admin
const serviceAccount = require('../serviceAccountKey.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  databaseURL: 'https://abra-fleet-default-rtdb.firebaseio.com'
});

// MongoDB connection string from your .env file
const MONGO_URI = 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';
const DB_NAME = 'abra_fleet';

async function migrateDrivers() {
  console.log('\n🚗 ========== DRIVER MIGRATION STARTED ==========\n');
  console.log('📊 Configuration:');
  console.log('   Database:', DB_NAME);
  console.log('   MongoDB URI: mongodb+srv://fleetadmin:***@cluster0.cnb4jvy.mongodb.net/...');
  console.log('\n');
  
  const client = new MongoClient(MONGO_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db(DB_NAME);
    const driversCollection = db.collection('drivers');
    const adminUsersCollection = db.collection('admin_users');
    
    // Get all drivers
    console.log('🔍 Fetching all drivers from database...');
    const drivers = await driversCollection.find({}).toArray();
    console.log(`📊 Found ${drivers.length} drivers to migrate\n`);
    
    if (drivers.length === 0) {
      console.log('⚠️  No drivers found in database');
      console.log('   Collection "drivers" is empty or doesn\'t exist');
      return;
    }
    
    let migratedCount = 0;
    let skippedCount = 0;
    let errorCount = 0;
    
    for (let i = 0; i < drivers.length; i++) {
      const driver = drivers[i];
      const email = driver.personalInfo?.email || driver.email;
      const firstName = driver.personalInfo?.firstName || driver.name?.split(' ')[0] || '';
      const lastName = driver.personalInfo?.lastName || driver.name?.split(' ').slice(1).join(' ') || '';
      const phone = driver.personalInfo?.phone || driver.phone;
      const driverId = driver.driverId;
      const firebaseUid = driver.uid || driver.firebaseUid;
      
      console.log(`\n[${i + 1}/${drivers.length}] 🔄 Processing: ${firstName} ${lastName}`);
      console.log(`   Email: ${email}`);
      console.log(`   Driver ID: ${driverId}`);
      console.log(`   Firebase UID: ${firebaseUid || 'MISSING'}`);
      
      // Skip if no email
      if (!email || email === 'N/A') {
        console.log('   ⚠️  SKIPPED - No valid email');
        skippedCount++;
        continue;
      }
      
      // Check if already exists in admin_users
      const existingAdminUser = await adminUsersCollection.findOne({
        email: email.toLowerCase()
      });
      
      if (existingAdminUser) {
        console.log('   ⏭️  SKIPPED - Already exists in admin_users');
        skippedCount++;
        continue;
      }
      
      // If no Firebase UID, create Firebase Auth user
      let finalFirebaseUid = firebaseUid;
      
      if (!finalFirebaseUid) {
        console.log('   🔐 Creating Firebase Auth user...');
        try {
          // Check if Firebase user already exists
          let firebaseUser;
          try {
            firebaseUser = await admin.auth().getUserByEmail(email);
            finalFirebaseUid = firebaseUser.uid;
            console.log('   ✅ Found existing Firebase user:', finalFirebaseUid);
          } catch (notFoundError) {
            // Create new Firebase user
            const tempPassword = Math.random().toString(36).slice(-12) + 'Aa1!';
            firebaseUser = await admin.auth().createUser({
              email: email,
              emailVerified: false,
              password: tempPassword,
              displayName: `${firstName} ${lastName}`,
              disabled: false
            });
            finalFirebaseUid = firebaseUser.uid;
            console.log('   ✅ Created new Firebase user:', finalFirebaseUid);
            
            // Set custom claims
            await admin.auth().setCustomUserClaims(finalFirebaseUid, {
              role: 'driver',
              driverId: driverId
            });
            console.log('   ✅ Set custom claims: role=driver');
          }
        } catch (firebaseError) {
          console.error('   ❌ Firebase error:', firebaseError.message);
          errorCount++;
          continue;
        }
      }
      
      // Create admin_users record
      const adminUserRecord = {
        firebaseUid: finalFirebaseUid,
        email: email.toLowerCase(),
        name: `${firstName} ${lastName}`.trim() || 'Unknown Driver',
        role: 'driver',
        phone: phone || '',
        status: driver.status || 'active',
        driverId: driverId,
        modules: [],
        permissions: {},
        createdAt: driver.createdAt || new Date(),
        updatedAt: new Date(),
        lastActive: new Date()
      };
      
      try {
        await adminUsersCollection.insertOne(adminUserRecord);
        console.log('   ✅ Inserted into admin_users');
        migratedCount++;
        
        // Update driver record with Firebase UID if it was missing
        if (!firebaseUid && finalFirebaseUid) {
          await driversCollection.updateOne(
            { _id: driver._id },
            { $set: { uid: finalFirebaseUid, firebaseUid: finalFirebaseUid, updatedAt: new Date() } }
          );
          console.log('   ✅ Updated driver with Firebase UID');
        }
      } catch (insertError) {
        console.error('   ❌ Insert error:', insertError.message);
        errorCount++;
      }
    }
    
    console.log('\n========== MIGRATION COMPLETE ==========');
    console.log(`✅ Migrated: ${migratedCount}`);
    console.log(`⏭️  Skipped: ${skippedCount}`);
    console.log(`❌ Errors: ${errorCount}`);
    console.log(`📊 Total: ${drivers.length}`);
    console.log('=========================================\n');
    
  } catch (error) {
    console.error('\n❌ ========== MIGRATION FAILED ==========');
    console.error('Error:', error.message);
    console.error('Stack trace:', error.stack);
    console.error('==========================================\n');
    throw error;
  } finally {
    await client.close();
    console.log('✅ MongoDB connection closed');
    await admin.app().delete();
    console.log('✅ Firebase connection closed');
  }
}

// Run the migration
migrateDrivers()
  .then(() => {
    console.log('✅ Migration script completed successfully');
    process.exit(0);
  })
  .catch((error) => {
    console.error('❌ Migration script failed:', error);
    process.exit(1);
  });