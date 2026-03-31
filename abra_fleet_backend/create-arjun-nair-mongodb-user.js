// Script to create Arjun Nair user in MongoDB database
const { MongoClient } = require('mongodb');
const admin = require('./config/firebase.js');
require('dotenv').config();

// MongoDB connection string from environment
const MONGODB_URI = process.env.MONGODB_URI;

async function createArjunNairInMongoDB() {
  console.log('🔧 Creating Arjun Nair user in MongoDB...\n');

  let client;
  try {
    // Connect to MongoDB
    client = new MongoClient(MONGODB_URI);
    await client.connect();
    console.log('✅ Connected to MongoDB');

    const db = client.db();
    const usersCollection = db.collection('users');

    // Get Firebase user details
    const firebaseUser = await admin.auth().getUserByEmail('arjun.nair@wipro.com');
    console.log(`✅ Found Firebase user: ${firebaseUser.uid}`);

    // Check if user already exists in MongoDB
    const existingUser = await usersCollection.findOne({ 
      $or: [
        { email: 'arjun.nair@wipro.com' },
        { firebaseUid: firebaseUser.uid }
      ]
    });

    if (existingUser) {
      console.log('⚠️  User already exists in MongoDB, updating...');
      
      // Update existing user
      const updateResult = await usersCollection.updateOne(
        { _id: existingUser._id },
        {
          $set: {
            firebaseUid: firebaseUser.uid,
            name: 'Arjun Nair',
            email: 'arjun.nair@wipro.com',
            role: 'Customer',
            companyName: 'Wipro',
            department: 'Testing',
            phone: '9876543220',
            status: 'Active',
            updatedAt: new Date()
          }
        }
      );
      
      console.log(`✅ Updated user in MongoDB: ${updateResult.modifiedCount} document(s) modified`);
    } else {
      console.log('📝 Creating new user in MongoDB...');
      
      // Create new user document
      const newUser = {
        firebaseUid: firebaseUser.uid,
        name: 'Arjun Nair',
        email: 'arjun.nair@wipro.com',
        role: 'Customer',
        companyName: 'Wipro',
        department: 'Testing',
        phone: '9876543220',
        alternativePhone: null,
        employeeId: null,
        designation: null,
        status: 'Active',
        emergencyContactName: null,
        emergencyContactPhone: null,
        createdAt: new Date(),
        updatedAt: new Date()
      };

      const insertResult = await usersCollection.insertOne(newUser);
      console.log(`✅ Created user in MongoDB: ${insertResult.insertedId}`);
    }

    // Verify the user exists and can be found by email
    const verifyUser = await usersCollection.findOne({ email: 'arjun.nair@wipro.com' });
    if (verifyUser) {
      console.log('\n✅ User verification successful:');
      console.log(`   MongoDB ID: ${verifyUser._id}`);
      console.log(`   Firebase UID: ${verifyUser.firebaseUid}`);
      console.log(`   Name: ${verifyUser.name}`);
      console.log(`   Email: ${verifyUser.email}`);
      console.log(`   Role: ${verifyUser.role}`);
      console.log(`   Company: ${verifyUser.companyName}`);
      console.log(`   Status: ${verifyUser.status}`);
    }

    console.log('\n🎉 MongoDB user setup complete!');
    console.log('   The user should now be found by the verify-email API endpoint.');

  } catch (error) {
    console.error('❌ Error creating user in MongoDB:', error);
  } finally {
    if (client) {
      await client.close();
      console.log('📝 MongoDB connection closed');
    }
  }
}

// Run the script
createArjunNairInMongoDB();