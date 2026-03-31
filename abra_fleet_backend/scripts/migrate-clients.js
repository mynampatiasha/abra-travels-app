// scripts/migrate-clients.js
// Run this ONCE to migrate all existing clients to admin_users collection

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

async function migrateClients() {
  console.log('\n🏢 ========== CLIENT MIGRATION STARTED ==========\n');
  console.log('📊 Configuration:');
  console.log('   Database:', DB_NAME);
  console.log('   MongoDB URI: mongodb+srv://fleetadmin:***@cluster0.cnb4jvy.mongodb.net/...');
  console.log('\n');
  
  const client = new MongoClient(MONGO_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db(DB_NAME);
    const adminUsersCollection = db.collection('admin_users');
    
    // Get all clients from Firebase Realtime Database
    console.log('📡 Fetching clients from Firebase Realtime Database...');
    const clientsRef = admin.database().ref('clients');
    const clientsSnapshot = await clientsRef.once('value');
    
    if (!clientsSnapshot.exists()) {
      console.log('⚠️  No clients found in Firebase Realtime Database');
      console.log('   Checking MongoDB customers collection as fallback...');
      
      // Check if there's a customers collection in MongoDB
      const customersCollection = db.collection('customers');
      const customers = await customersCollection.find({}).toArray();
      
      if (customers.length === 0) {
        console.log('⚠️  No customers found in MongoDB either');
        console.log('   Nothing to migrate - no clients exist');
        return;
      }
      
      console.log(`📊 Found ${customers.length} customers in MongoDB to migrate as clients\n`);
      
      // Migrate from MongoDB customers collection
      let migratedCount = 0;
      let skippedCount = 0;
      let errorCount = 0;
      
      for (let i = 0; i < customers.length; i++) {
        const customer = customers[i];
        const email = customer.email;
        const name = customer.name || 'Unknown Customer';
        const phoneNumber = customer.phoneNumber || customer.phone || '';
        const organizationName = customer.organizationName || customer.companyName || '';
        
        console.log(`\n[${i + 1}/${customers.length}] 🔄 Processing: ${name}`);
        console.log(`   Email: ${email}`);
        console.log(`   Organization: ${organizationName}`);
        
        if (!email) {
          console.log('   ⚠️  SKIPPED - No email');
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
        
        // Get or create Firebase Auth user
        let firebaseUid;
        try {
          const firebaseUser = await admin.auth().getUserByEmail(email);
          firebaseUid = firebaseUser.uid;
          console.log('   ✅ Found existing Firebase user:', firebaseUid);
          
          await admin.auth().setCustomUserClaims(firebaseUid, { role: 'client' });
          console.log('   ✅ Updated custom claims: role=client');
        } catch (notFoundError) {
          console.log('   🔐 Creating new Firebase Auth user...');
          try {
            const tempPassword = Math.random().toString(36).slice(-12) + 'Aa1!';
            const newFirebaseUser = await admin.auth().createUser({
              email: email,
              emailVerified: false,
              password: tempPassword,
              displayName: name,
              disabled: false
            });
            
            firebaseUid = newFirebaseUser.uid;
            console.log('   ✅ Created Firebase user:', firebaseUid);
            
            await admin.auth().setCustomUserClaims(firebaseUid, { role: 'client' });
            console.log('   ✅ Set custom claims: role=client');
          } catch (createError) {
            console.error('   ❌ Firebase creation error:', createError.message);
            errorCount++;
            continue;
          }
        }
        
        // Create admin_users record
        const adminUserRecord = {
          firebaseUid: firebaseUid,
          email: email.toLowerCase(),
          name: name,
          role: 'client',
          phoneNumber: phoneNumber,
          phone: phoneNumber,
          organizationName: organizationName,
          companyName: organizationName,
          status: customer.status || 'active',
          modules: [],
          permissions: {},
          createdAt: customer.createdAt || new Date(),
          updatedAt: new Date(),
          lastActive: new Date()
        };
        
        try {
          await adminUsersCollection.insertOne(adminUserRecord);
          console.log('   ✅ Inserted into admin_users');
          migratedCount++;
        } catch (insertError) {
          console.error('   ❌ Insert error:', insertError.message);
          errorCount++;
        }
      }
      
      console.log('\n========== MIGRATION COMPLETE ==========');
      console.log(`✅ Migrated: ${migratedCount}`);
      console.log(`⏭️  Skipped: ${skippedCount}`);
      console.log(`❌ Errors: ${errorCount}`);
      console.log(`📊 Total: ${customers.length}`);
      console.log('=========================================\n');
      
      return;
    }
    
    // Migrate from Firebase Realtime Database
    const clients = clientsSnapshot.val();
    const clientEntries = Object.entries(clients);
    console.log(`📊 Found ${clientEntries.length} clients in Firebase Realtime DB to migrate\n`);
    
    let migratedCount = 0;
    let skippedCount = 0;
    let errorCount = 0;
    
    for (let i = 0; i < clientEntries.length; i++) {
      const [clientId, clientData] = clientEntries[i];
      const email = clientData.email;
      const name = clientData.name || 'Unknown Client';
      const phoneNumber = clientData.phoneNumber || '';
      const organizationName = clientData.organizationName || clientData.companyName || '';
      
      console.log(`\n[${i + 1}/${clientEntries.length}] 🔄 Processing: ${name}`);
      console.log(`   Email: ${email}`);
      console.log(`   Client ID: ${clientId}`);
      console.log(`   Organization: ${organizationName}`);
      
      if (!email) {
        console.log('   ⚠️  SKIPPED - No email');
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
      
      // Get or create Firebase Auth user
      let firebaseUid;
      try {
        const firebaseUser = await admin.auth().getUserByEmail(email);
        firebaseUid = firebaseUser.uid;
        console.log('   ✅ Found existing Firebase user:', firebaseUid);
        
        await admin.auth().setCustomUserClaims(firebaseUid, { role: 'client' });
        console.log('   ✅ Updated custom claims: role=client');
      } catch (notFoundError) {
        console.log('   🔐 Creating new Firebase Auth user...');
        try {
          const tempPassword = Math.random().toString(36).slice(-12) + 'Aa1!';
          const newFirebaseUser = await admin.auth().createUser({
            email: email,
            emailVerified: false,
            password: tempPassword,
            displayName: name,
            disabled: false
          });
          
          firebaseUid = newFirebaseUser.uid;
          console.log('   ✅ Created Firebase user:', firebaseUid);
          
          await admin.auth().setCustomUserClaims(firebaseUid, { role: 'client' });
          console.log('   ✅ Set custom claims: role=client');
        } catch (createError) {
          console.error('   ❌ Firebase creation error:', createError.message);
          errorCount++;
          continue;
        }
      }
      
      // Create admin_users record
      const adminUserRecord = {
        firebaseUid: firebaseUid,
        email: email.toLowerCase(),
        name: name,
        role: 'client',
        phoneNumber: phoneNumber,
        phone: phoneNumber,
        organizationName: organizationName,
        companyName: organizationName,
        status: 'active',
        modules: [],
        permissions: {},
        createdAt: clientData.createdAt ? new Date(clientData.createdAt) : new Date(),
        updatedAt: new Date(),
        lastActive: new Date()
      };
      
      try {
        await adminUsersCollection.insertOne(adminUserRecord);
        console.log('   ✅ Inserted into admin_users');
        migratedCount++;
      } catch (insertError) {
        console.error('   ❌ Insert error:', insertError.message);
        errorCount++;
      }
    }
    
    console.log('\n========== MIGRATION COMPLETE ==========');
    console.log(`✅ Migrated: ${migratedCount}`);
    console.log(`⏭️  Skipped: ${skippedCount}`);
    console.log(`❌ Errors: ${errorCount}`);
    console.log(`📊 Total: ${clientEntries.length}`);
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
migrateClients()
  .then(() => {
    console.log('✅ Migration script completed successfully');
    process.exit(0);
  })
  .catch((error) => {
    console.error('❌ Migration script failed:', error);
    process.exit(1);
  });