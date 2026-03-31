// create-test-customers.js - Create test customer accounts for roster testing
const admin = require('firebase-admin');
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

// Initialize Firebase Admin
const serviceAccount = require('./config/firebase-service-account.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

// Test customers from your roster import
const testCustomers = [
  {
    name: 'Pooja Joshi',
    email: 'pooja.joshi@wipro.com',
    phone: '+919876543210',
    companyName: 'Wipro Limited',
    department: 'Engineering'
  },
  {
    name: 'Arjun Nair',
    email: 'arjun.nair@wipro.com',
    phone: '+919876543211',
    companyName: 'Wipro Limited',
    department: 'Engineering'
  },
  {
    name: 'Sneha Iyer',
    email: 'sneha.iyer@wipro.com',
    phone: '+919876543212',
    companyName: 'Wipro Limited',
    department: 'Engineering'
  }
];

async function createTestCustomers() {
  console.log('\n' + '='.repeat(80));
  console.log('🚀 CREATING TEST CUSTOMER ACCOUNTS');
  console.log('='.repeat(80));
  
  let mongoClient;
  
  try {
    // Connect to MongoDB
    const mongoUri = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';
    mongoClient = new MongoClient(mongoUri);
    await mongoClient.connect();
    const db = mongoClient.db();
    
    console.log('✅ Connected to MongoDB\n');
    
    const results = {
      created: [],
      existing: [],
      failed: []
    };
    
    for (const customer of testCustomers) {
      console.log(`\n📋 Processing: ${customer.name} (${customer.email})`);
      console.log('-'.repeat(80));
      
      try {
        // Check if user already exists in Firebase
        let firebaseUser;
        try {
          firebaseUser = await admin.auth().getUserByEmail(customer.email);
          console.log(`   ℹ️  Firebase user already exists: ${firebaseUser.uid}`);
        } catch (error) {
          if (error.code === 'auth/user-not-found') {
            // Create Firebase Auth user
            console.log('   🔐 Creating Firebase Auth user...');
            const tempPassword = 'Welcome@123'; // Temporary password
            
            firebaseUser = await admin.auth().createUser({
              email: customer.email,
              password: tempPassword,
              displayName: customer.name,
              emailVerified: false
            });
            
            console.log(`   ✅ Firebase user created: ${firebaseUser.uid}`);
            console.log(`   🔑 Temporary password: ${tempPassword}`);
            
            // Generate password reset link
            try {
              const passwordResetLink = await admin.auth().generatePasswordResetLink(customer.email);
              console.log(`   📧 Password reset link generated`);
              console.log(`   🔗 Link: ${passwordResetLink.substring(0, 50)}...`);
            } catch (linkError) {
              console.log(`   ⚠️  Could not generate password reset link: ${linkError.message}`);
            }
          } else {
            throw error;
          }
        }
        
        // Check if user exists in MongoDB
        const existingMongoUser = await db.collection('users').findOne({
          email: customer.email
        });
        
        if (existingMongoUser) {
          console.log(`   ℹ️  MongoDB user already exists: ${existingMongoUser._id}`);
          
          // Update Firebase UID if missing
          if (!existingMongoUser.firebaseUid) {
            await db.collection('users').updateOne(
              { _id: existingMongoUser._id },
              { $set: { firebaseUid: firebaseUser.uid, updatedAt: new Date() } }
            );
            console.log(`   ✅ Updated MongoDB user with Firebase UID`);
          }
          
          results.existing.push({
            name: customer.name,
            email: customer.email,
            firebaseUid: firebaseUser.uid,
            mongoId: existingMongoUser._id.toString()
          });
        } else {
          // Create MongoDB user document
          console.log('   💾 Creating MongoDB user document...');
          
          const mongoUser = {
            firebaseUid: firebaseUser.uid,
            email: customer.email,
            name: customer.name,
            phone: customer.phone,
            role: 'customer',
            companyName: customer.companyName,
            organizationName: customer.companyName,
            department: customer.department,
            status: 'active',
            isApproved: true,
            createdAt: new Date(),
            createdBy: 'test_script',
            updatedAt: new Date()
          };
          
          const insertResult = await db.collection('users').insertOne(mongoUser);
          console.log(`   ✅ MongoDB user created: ${insertResult.insertedId}`);
          
          results.created.push({
            name: customer.name,
            email: customer.email,
            firebaseUid: firebaseUser.uid,
            mongoId: insertResult.insertedId.toString(),
            tempPassword: 'Welcome@123'
          });
        }
        
        // Update rosters with user ID
        console.log('   🔗 Linking rosters to user...');
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
              updatedAt: new Date()
            } 
          }
        );
        
        if (updateResult.modifiedCount > 0) {
          console.log(`   ✅ Linked ${updateResult.modifiedCount} roster(s) to user`);
        } else {
          console.log(`   ℹ️  No rosters found to link`);
        }
        
      } catch (customerError) {
        console.error(`   ❌ Failed to create customer: ${customerError.message}`);
        results.failed.push({
          name: customer.name,
          email: customer.email,
          error: customerError.message
        });
      }
    }
    
    // Print summary
    console.log('\n' + '='.repeat(80));
    console.log('📊 SUMMARY');
    console.log('='.repeat(80));
    console.log(`✅ Created: ${results.created.length}`);
    console.log(`ℹ️  Already Existed: ${results.existing.length}`);
    console.log(`❌ Failed: ${results.failed.length}`);
    
    if (results.created.length > 0) {
      console.log('\n🔑 NEW ACCOUNTS (Temporary Password: Welcome@123):');
      results.created.forEach(user => {
        console.log(`   - ${user.name} (${user.email})`);
        console.log(`     Firebase UID: ${user.firebaseUid}`);
        console.log(`     MongoDB ID: ${user.mongoId}`);
      });
      console.log('\n💡 Users should reset their password on first login');
    }
    
    if (results.existing.length > 0) {
      console.log('\n📋 EXISTING ACCOUNTS:');
      results.existing.forEach(user => {
        console.log(`   - ${user.name} (${user.email})`);
      });
    }
    
    if (results.failed.length > 0) {
      console.log('\n❌ FAILED:');
      results.failed.forEach(user => {
        console.log(`   - ${user.name} (${user.email}): ${user.error}`);
      });
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('✅ TEST CUSTOMER CREATION COMPLETE');
    console.log('='.repeat(80));
    console.log('\n💡 NEXT STEPS:');
    console.log('   1. Users can now log in with their email and password: Welcome@123');
    console.log('   2. They should reset their password on first login');
    console.log('   3. FCM tokens will be registered automatically when they log in via app');
    console.log('   4. Re-run route optimization to test notifications');
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

// Run the script
createTestCustomers();
