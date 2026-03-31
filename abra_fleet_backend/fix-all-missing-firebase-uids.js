const { MongoClient } = require('mongodb');
const admin = require('firebase-admin');
const FirebaseUidManager = require('./utils/firebase_uid_manager');

// Initialize Firebase Admin (if not already initialized)
if (!admin.apps.length) {
  try {
    const serviceAccount = require('./serviceAccountKey.json');
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      projectId: 'abrafleet-cec94',
      databaseURL: 'https://abrafleet-cec94-default-rtdb.firebaseio.com'
    });
    console.log('✅ Firebase Admin initialized');
  } catch (error) {
    console.error('❌ Firebase Admin initialization failed:', error.message);
    process.exit(1);
  }
}

async function fixAllMissingFirebaseUids() {
  let client;
  
  try {
    // Connect to MongoDB
    console.log('🔌 Connecting to MongoDB...');
    const mongoUri = process.env.MONGODB_URI || 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';
    client = new MongoClient(mongoUri);
    await client.connect();
    
    const db = client.db();
    console.log('✅ Connected to MongoDB');
    
    // Initialize Firebase UID Manager
    const uidManager = new FirebaseUidManager(db);
    
    // Collections to process
    const collections = [
      'drivers',
      'employee_admins',
      'admin_users', 
      'customers',
      'users',
      'clients'
    ];
    
    console.log('\n🚀 ========== STARTING FIREBASE UID BACKFILL ==========');
    console.log('Collections to process:', collections);
    
    const overallResults = {
      totalProcessed: 0,
      totalSuccess: 0,
      totalFailed: 0,
      collectionResults: {}
    };
    
    // Process each collection
    for (const collectionName of collections) {
      try {
        console.log(`\n📋 Processing collection: ${collectionName}`);
        
        // Check if collection exists
        const collectionExists = await db.listCollections({ name: collectionName }).hasNext();
        if (!collectionExists) {
          console.log(`⚠️ Collection ${collectionName} does not exist, skipping...`);
          continue;
        }
        
        // Get collection stats
        const totalCount = await db.collection(collectionName).countDocuments();
        const missingUidCount = await db.collection(collectionName).countDocuments({
          $or: [
            { firebaseUid: { $exists: false } },
            { firebaseUid: null },
            { firebaseUid: '' }
          ],
          email: { $exists: true, $ne: '' }
        });
        
        console.log(`Total users in ${collectionName}: ${totalCount}`);
        console.log(`Users missing Firebase UID: ${missingUidCount}`);
        
        if (missingUidCount === 0) {
          console.log('✅ No users missing Firebase UID in this collection');
          overallResults.collectionResults[collectionName] = {
            processed: 0,
            success: 0,
            failed: 0,
            errors: []
          };
          continue;
        }
        
        // Process in batches to avoid overwhelming Firebase
        const batchSize = 10;
        let processed = 0;
        
        while (processed < missingUidCount) {
          console.log(`\nProcessing batch ${Math.floor(processed / batchSize) + 1}...`);
          
          const results = await uidManager.backfillMissingFirebaseUids(collectionName, batchSize);
          
          // Update overall results
          overallResults.totalProcessed += results.processed;
          overallResults.totalSuccess += results.success;
          overallResults.totalFailed += results.failed;
          
          if (!overallResults.collectionResults[collectionName]) {
            overallResults.collectionResults[collectionName] = {
              processed: 0,
              success: 0,
              failed: 0,
              errors: []
            };
          }
          
          overallResults.collectionResults[collectionName].processed += results.processed;
          overallResults.collectionResults[collectionName].success += results.success;
          overallResults.collectionResults[collectionName].failed += results.failed;
          overallResults.collectionResults[collectionName].errors.push(...results.errors);
          
          processed += results.processed;
          
          // Break if no more users to process
          if (results.processed < batchSize) {
            break;
          }
          
          // Small delay between batches
          await new Promise(resolve => setTimeout(resolve, 1000));
        }
        
      } catch (error) {
        console.error(`❌ Error processing collection ${collectionName}:`, error.message);
        overallResults.collectionResults[collectionName] = {
          processed: 0,
          success: 0,
          failed: 1,
          errors: [{ collection: collectionName, error: error.message }]
        };
      }
    }
    
    // Print final results
    console.log('\n🎉 ========== FINAL RESULTS ==========');
    console.log('Total users processed:', overallResults.totalProcessed);
    console.log('Total successful:', overallResults.totalSuccess);
    console.log('Total failed:', overallResults.totalFailed);
    
    console.log('\n📊 Results by collection:');
    for (const [collection, results] of Object.entries(overallResults.collectionResults)) {
      console.log(`\n${collection}:`);
      console.log(`  Processed: ${results.processed}`);
      console.log(`  Success: ${results.success}`);
      console.log(`  Failed: ${results.failed}`);
      
      if (results.errors.length > 0) {
        console.log('  Errors:');
        results.errors.forEach((error, index) => {
          console.log(`    ${index + 1}. ${error.email}: ${error.error}`);
        });
      }
    }
    
    // Verification step
    console.log('\n🔍 ========== VERIFICATION ==========');
    for (const collectionName of collections) {
      try {
        const stillMissing = await db.collection(collectionName).countDocuments({
          $or: [
            { firebaseUid: { $exists: false } },
            { firebaseUid: null },
            { firebaseUid: '' }
          ],
          email: { $exists: true, $ne: '' }
        });
        
        console.log(`${collectionName}: ${stillMissing} users still missing Firebase UID`);
      } catch (error) {
        console.log(`${collectionName}: Could not verify (${error.message})`);
      }
    }
    
    console.log('\n✅ Firebase UID backfill completed!');
    
    if (overallResults.totalFailed > 0) {
      console.log('\n⚠️ Some users failed to get Firebase UIDs. Check the errors above.');
      console.log('You may need to manually review and fix these users.');
    }
    
  } catch (error) {
    console.error('❌ Script failed:', error.message);
    console.error(error.stack);
  } finally {
    if (client) {
      await client.close();
      console.log('🔌 MongoDB connection closed');
    }
  }
}

// Run the script
if (require.main === module) {
  fixAllMissingFirebaseUids()
    .then(() => {
      console.log('\n🎯 Script completed successfully!');
      process.exit(0);
    })
    .catch((error) => {
      console.error('\n💥 Script failed:', error.message);
      process.exit(1);
    });
}

module.exports = { fixAllMissingFirebaseUids };