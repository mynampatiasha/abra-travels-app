// migrate-roster-customers-to-firebase.js
// Find all customers with assigned rosters and create Firebase/MongoDB accounts for them
const admin = require('firebase-admin');
const { MongoClient } = require('mongodb');
require('dotenv').config();

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'abrafleet-cec94',
  databaseURL: 'https://abrafleet-cec94-default-rtdb.firebaseio.com'
});

async function migrateRosterCustomersToFirebase() {
  console.log('\n' + '='.repeat(80));
  console.log('🔄 MIGRATING ROSTER CUSTOMERS TO FIREBASE & MONGODB');
  console.log('='.repeat(80));
  
  let mongoClient;
  
  try {
    // Connect to MongoDB
    const mongoUri = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';
    mongoClient = new MongoClient(mongoUri);
    await mongoClient.connect();
    const db = mongoClient.db();
    
    console.log('✅ Connected to MongoDB\n');
    
    // ========== STEP 1: FIND ALL UNIQUE CUSTOMERS FROM ROSTERS ==========
    console.log('📋 STEP 1: Finding all unique customers from rosters...');
    console.log('-'.repeat(80));
    
    const rosters = await db.collection('rosters').find({}).toArray();
    console.log(`Total rosters found: ${rosters.length}`);
    
    // Extract unique customers
    const customersMap = new Map();
    
    rosters.forEach(roster => {
      const email = roster.customerEmail || 
                   roster.employeeDetails?.email || 
                   roster.employeeData?.email;
      
      if (email && !customersMap.has(email.toLowerCase())) {
        const name = roster.customerName || 
                    roster.employeeDetails?.name || 
                    roster.employeeData?.name || 
                    'Unknown';
        
        const phone = roster.employeeDetails?.phone || 
                     roster.employeeData?.phone || 
                     '';
        
        const organization = roster.organizationName || 
                           roster.companyName || 
                           roster.employeeDetails?.companyName || 
                           roster.employeeData?.companyName || 
                           'Unknown Organization';
        
        const department = roster.employeeDetails?.department || 
                          roster.employeeData?.department || 
                          '';
        
        customersMap.set(email.toLowerCase(), {
          email: email.toLowerCase(),
          name: name,
          phone: phone,
          organization: organization,
          department: department,
          rosterCount: 1,
          rosterIds: [roster._id.toString()],
          status: roster.status
        });
      } else if (email) {
        // Increment roster count for existing customer
        const customer = customersMap.get(email.toLowerCase());
        customer.rosterCount++;
        customer.rosterIds.push(roster._id.toString());
      }
    });
    
    const uniqueCustomers = Array.from(customersMap.values());
    console.log(`\n✅ Found ${uniqueCustomers.length} unique customers in rosters\n`);
    
    // Show sample customers
    console.log('📊 Sample Customers:');
    uniqueCustomers.slice(0, 5).forEach((customer, idx) => {
      console.log(`   ${idx + 1}. ${customer.name} (${customer.email})`);
      console.log(`      Organization: ${customer.organization}`);
      console.log(`      Rosters: ${customer.rosterCount}`);
    });
    if (uniqueCustomers.length > 5) {
      console.log(`   ... and ${uniqueCustomers.length - 5} more`);
    }
    
    // ========== STEP 2: CHECK WHICH CUSTOMERS ALREADY EXIST ==========
    console.log('\n\n📋 STEP 2: Checking which customers already have accounts...');
    console.log('-'.repeat(80));
    
    const existingMongoUsers = await db.collection('users').find({
      email: { $in: uniqueCustomers.map(c => c.email) }
    }).toArray();
    
    const existingEmailsSet = new Set(existingMongoUsers.map(u => u.email.toLowerCase()));
    
    const customersToCreate = uniqueCustomers.filter(c => !existingEmailsSet.has(c.email));
    const customersAlreadyExist = uniqueCustomers.filter(c => existingEmailsSet.has(c.email));
    
    console.log(`\n✅ Already have accounts: ${customersAlreadyExist.length}`);
    console.log(`🆕 Need to create accounts: ${customersToCreate.length}`);
    
    if (customersAlreadyExist.length > 0) {
      console.log('\n📋 Customers with existing accounts:');
      customersAlreadyExist.slice(0, 5).forEach(customer => {
        console.log(`   - ${customer.name} (${customer.email})`);
      });
      if (customersAlreadyExist.length > 5) {
        console.log(`   ... and ${customersAlreadyExist.length - 5} more`);
      }
    }
    
    if (customersToCreate.length === 0) {
      console.log('\n✅ All roster customers already have accounts!');
      console.log('='.repeat(80));
      return;
    }
    
    // ========== STEP 3: CREATE ACCOUNTS FOR MISSING CUSTOMERS ==========
    console.log('\n\n📋 STEP 3: Creating accounts for missing customers...');
    console.log('-'.repeat(80));
    
    const results = {
      created: [],
      failed: [],
      skipped: []
    };
    
    for (let i = 0; i < customersToCreate.length; i++) {
      const customer = customersToCreate[i];
      console.log(`\n[${i + 1}/${customersToCreate.length}] Processing: ${customer.name} (${customer.email})`);
      console.log('-'.repeat(60));
      
      try {
        // Check if user exists in Firebase Auth
        let firebaseUser;
        try {
          firebaseUser = await admin.auth().getUserByEmail(customer.email);
          console.log(`   ℹ️  Firebase Auth user already exists: ${firebaseUser.uid}`);
        } catch (fbError) {
          if (fbError.code === 'auth/user-not-found') {
            // Create Firebase Auth user
            console.log('   🔐 Creating Firebase Auth user...');
            const tempPassword = 'Welcome@' + Math.random().toString(36).slice(-8);
            
            firebaseUser = await admin.auth().createUser({
              email: customer.email,
              password: tempPassword,
              displayName: customer.name,
              emailVerified: false
            });
            
            console.log(`   ✅ Firebase Auth user created: ${firebaseUser.uid}`);
            console.log(`   🔑 Temporary password: ${tempPassword}`);
            
            // Generate password reset link
            try {
              const passwordResetLink = await admin.auth().generatePasswordResetLink(customer.email);
              console.log(`   📧 Password reset link generated`);
              console.log(`   🔗 ${passwordResetLink.substring(0, 60)}...`);
            } catch (linkError) {
              console.warn(`   ⚠️  Could not generate password reset link: ${linkError.message}`);
            }
          } else {
            throw fbError;
          }
        }
        
        // Create MongoDB user document
        console.log('   💾 Creating MongoDB user document...');
        const mongoUser = {
          firebaseUid: firebaseUser.uid,
          email: customer.email,
          name: customer.name,
          phone: customer.phone,
          role: 'customer',
          companyName: customer.organization,
          organizationName: customer.organization,
          department: customer.department,
          status: 'active',
          isApproved: true,
          createdAt: new Date(),
          createdBy: 'migration_script',
          createdVia: 'roster_migration',
          updatedAt: new Date(),
          metadata: {
            rosterCount: customer.rosterCount,
            migratedFrom: 'rosters',
            migrationDate: new Date()
          }
        };
        
        const insertResult = await db.collection('users').insertOne(mongoUser);
        console.log(`   ✅ MongoDB user created: ${insertResult.insertedId}`);
        
        // Update rosters with user ID
        console.log(`   🔗 Linking ${customer.rosterCount} roster(s) to user...`);
        const updateResult = await db.collection('rosters').updateMany(
          { 
            $or: [
              { customerEmail: customer.email },
              { 'employeeDetails.email': customer.email },
              { 'employeeData.email': customer.email }
            ]
          },
          { 
            $set: { 
              customerId: firebaseUser.uid,
              customerFirebaseUid: firebaseUser.uid,
              updatedAt: new Date(),
              updatedBy: 'migration_script'
            } 
          }
        );
        
        console.log(`   ✅ Linked ${updateResult.modifiedCount} roster(s)`);
        
        results.created.push({
          name: customer.name,
          email: customer.email,
          firebaseUid: firebaseUser.uid,
          mongoId: insertResult.insertedId.toString(),
          rostersLinked: updateResult.modifiedCount
        });
        
        console.log(`   ✅ SUCCESS: Account created and rosters linked`);
        
      } catch (customerError) {
        console.error(`   ❌ FAILED: ${customerError.message}`);
        results.failed.push({
          name: customer.name,
          email: customer.email,
          error: customerError.message
        });
      }
      
      // Small delay to avoid rate limiting
      if (i < customersToCreate.length - 1) {
        await new Promise(resolve => setTimeout(resolve, 500));
      }
    }
    
    // ========== STEP 4: UPDATE EXISTING USERS' ROSTERS ==========
    console.log('\n\n📋 STEP 4: Updating rosters for existing users...');
    console.log('-'.repeat(80));
    
    let rostersUpdated = 0;
    
    for (const customer of customersAlreadyExist) {
      const mongoUser = existingMongoUsers.find(u => u.email.toLowerCase() === customer.email);
      
      if (mongoUser && mongoUser.firebaseUid) {
        const updateResult = await db.collection('rosters').updateMany(
          { 
            $or: [
              { customerEmail: customer.email },
              { 'employeeDetails.email': customer.email },
              { 'employeeData.email': customer.email }
            ],
            customerId: { $exists: false } // Only update if not already linked
          },
          { 
            $set: { 
              customerId: mongoUser.firebaseUid,
              customerFirebaseUid: mongoUser.firebaseUid,
              updatedAt: new Date(),
              updatedBy: 'migration_script'
            } 
          }
        );
        
        if (updateResult.modifiedCount > 0) {
          console.log(`   ✅ Linked ${updateResult.modifiedCount} roster(s) for ${customer.name}`);
          rostersUpdated += updateResult.modifiedCount;
        }
      }
    }
    
    console.log(`\n✅ Updated ${rostersUpdated} rosters for existing users`);
    
    // ========== SUMMARY ==========
    console.log('\n\n' + '='.repeat(80));
    console.log('📊 MIGRATION SUMMARY');
    console.log('='.repeat(80));
    
    console.log(`\n📈 Statistics:`);
    console.log(`   Total unique customers in rosters: ${uniqueCustomers.length}`);
    console.log(`   Already had accounts: ${customersAlreadyExist.length}`);
    console.log(`   New accounts created: ${results.created.length}`);
    console.log(`   Failed to create: ${results.failed.length}`);
    console.log(`   Rosters updated for existing users: ${rostersUpdated}`);
    
    if (results.created.length > 0) {
      console.log(`\n✅ NEW ACCOUNTS CREATED (${results.created.length}):`);
      results.created.forEach((user, idx) => {
        console.log(`   ${idx + 1}. ${user.name} (${user.email})`);
        console.log(`      Firebase UID: ${user.firebaseUid}`);
        console.log(`      MongoDB ID: ${user.mongoId}`);
        console.log(`      Rosters Linked: ${user.rostersLinked}`);
      });
      console.log(`\n🔑 Temporary Password: Welcome@XXXXXXXX (random)`);
      console.log(`💡 Users should reset their password on first login`);
    }
    
    if (results.failed.length > 0) {
      console.log(`\n❌ FAILED TO CREATE (${results.failed.length}):`);
      results.failed.forEach((user, idx) => {
        console.log(`   ${idx + 1}. ${user.name} (${user.email})`);
        console.log(`      Error: ${user.error}`);
      });
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('✅ MIGRATION COMPLETE');
    console.log('='.repeat(80));
    
    console.log('\n💡 NEXT STEPS:');
    console.log('   1. Restart backend to ensure all changes are loaded');
    console.log('   2. Test login with migrated users');
    console.log('   3. Re-run route optimization to test notifications');
    console.log('   4. Send welcome emails to new users (if email service configured)');
    console.log('='.repeat(80) + '\n');
    
  } catch (error) {
    console.error('\n❌ FATAL ERROR:', error);
    console.error(error.stack);
  } finally {
    if (mongoClient) {
      await mongoClient.close();
      console.log('✅ MongoDB connection closed');
    }
    process.exit(0);
  }
}

// Run the migration
migrateRosterCustomersToFirebase();
