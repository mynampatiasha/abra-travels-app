/**
 * Migration Script: Firestore to MongoDB
 * 
 * This script copies all user data from Firestore to MongoDB
 * Run once: node scripts/migrate_firestore_to_mongodb.js
 */

const admin = require('../config/firebase');
const { MongoClient } = require('mongodb');
require('dotenv').config();

async function migrateUsers() {
  console.log('\n' + '='.repeat(80));
  console.log('FIRESTORE TO MONGODB USER MIGRATION');
  console.log('='.repeat(80) + '\n');

  let mongoClient;
  
  try {
    // Connect to MongoDB
    console.log('📡 Connecting to MongoDB...');
    const mongoUri = process.env.MONGODB_URI;
    
    if (!mongoUri) {
      throw new Error('MONGODB_URI not found in environment variables');
    }
    
    mongoClient = new MongoClient(mongoUri);
    await mongoClient.connect();
    const db = mongoClient.db('abra_fleet');
    console.log('✅ Connected to MongoDB\n');

    // Get Firestore users
    console.log('📡 Fetching users from Firestore...');
    const firestore = admin.firestore();
    const usersSnapshot = await firestore.collection('users').get();
    
    if (usersSnapshot.empty) {
      console.log('⚠️  No users found in Firestore');
      return;
    }
    
    console.log(`✅ Found ${usersSnapshot.size} users in Firestore\n`);

    // Migrate each user
    let successCount = 0;
    let skipCount = 0;
    let errorCount = 0;

    for (const doc of usersSnapshot.docs) {
      const firebaseUid = doc.id;
      const firestoreData = doc.data();
      
      try {
        console.log(`\n📝 Processing: ${firestoreData.email || firebaseUid}`);
        
        // Check if user already exists in MongoDB
        const existingUser = await db.collection('users').findOne({ firebaseUid });
        
        if (existingUser) {
          console.log('   ⏭️  User already exists in MongoDB - skipping');
          skipCount++;
          continue;
        }
        
        // Prepare user data for MongoDB
        const mongoUser = {
          firebaseUid,
          email: firestoreData.email || null,
          name: firestoreData.name || firestoreData.displayName || 'User',
          role: (firestoreData.role || 'customer').toLowerCase().trim(),
          phone: firestoreData.phoneNumber || firestoreData.phone || null,
          organizationId: firestoreData.organizationId || null,
          fcmToken: firestoreData.fcmToken || null,
          isActive: firestoreData.isActive !== false,
          profileImageUrl: firestoreData.profileImageUrl || null,
          
          // Timestamps
          createdAt: firestoreData.createdAt?.toDate() || new Date(),
          updatedAt: firestoreData.updatedAt?.toDate() || new Date(),
          lastLogin: firestoreData.lastLogin?.toDate() || null,
          
          // Migration metadata
          migratedFrom: 'firestore',
          migratedAt: new Date()
        };
        
        // Insert into MongoDB
        await db.collection('users').insertOne(mongoUser);
        
        console.log('   ✅ Migrated successfully');
        console.log(`      Email: ${mongoUser.email}`);
        console.log(`      Role: ${mongoUser.role}`);
        console.log(`      Name: ${mongoUser.name}`);
        
        successCount++;
        
      } catch (error) {
        console.error(`   ❌ Error migrating user: ${error.message}`);
        errorCount++;
      }
    }

    // Summary
    console.log('\n' + '='.repeat(80));
    console.log('MIGRATION SUMMARY');
    console.log('='.repeat(80));
    console.log(`✅ Successfully migrated: ${successCount}`);
    console.log(`⏭️  Skipped (already exist): ${skipCount}`);
    console.log(`❌ Errors: ${errorCount}`);
    console.log(`📊 Total processed: ${usersSnapshot.size}`);
    console.log('='.repeat(80) + '\n');

    // Verify migration
    console.log('🔍 Verifying migration...');
    const mongoUserCount = await db.collection('users').countDocuments();
    console.log(`📊 Total users in MongoDB: ${mongoUserCount}`);
    
    // Show sample users
    console.log('\n📋 Sample users in MongoDB:');
    const sampleUsers = await db.collection('users').find({}).limit(5).toArray();
    sampleUsers.forEach((user, index) => {
      console.log(`\n${index + 1}. ${user.email}`);
      console.log(`   Role: ${user.role}`);
      console.log(`   Firebase UID: ${user.firebaseUid}`);
      console.log(`   MongoDB ID: ${user._id}`);
    });

    console.log('\n✅ Migration completed successfully!\n');

  } catch (error) {
    console.error('\n❌ MIGRATION FAILED');
    console.error('Error:', error.message);
    console.error('Stack:', error.stack);
    process.exit(1);
    
  } finally {
    // Close MongoDB connection
    if (mongoClient) {
      await mongoClient.close();
      console.log('📡 MongoDB connection closed\n');
    }
  }
}

// Run migration
migrateUsers()
  .then(() => {
    console.log('🎉 All done!');
    process.exit(0);
  })
  .catch((error) => {
    console.error('💥 Fatal error:', error);
    process.exit(1);
  });
