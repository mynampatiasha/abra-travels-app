// migrate-firebase-notifications-to-mongodb.js
// Migrate old Firebase notifications to MongoDB

const admin = require('firebase-admin');
const { MongoClient } = require('mongodb');
require('dotenv').config();

// Initialize Firebase Admin
if (!admin.apps.length) {
  try {
    const serviceAccount = require('./serviceAccountKey.json');
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount)
    });
    console.log('✅ Firebase Admin initialized');
  } catch (error) {
    console.error('❌ Error initializing Firebase Admin:', error.message);
    console.log('\n⚠️  Make sure serviceAccountKey.json exists in abra_fleet_backend folder');
    process.exit(1);
  }
}

const firestore = admin.firestore();

async function migrateNotifications() {
  let mongoClient;
  
  try {
    console.log('🚀 Starting Firebase to MongoDB notification migration...\n');
    console.log('='.repeat(80));
    
    // Connect to MongoDB
    console.log('📡 Connecting to MongoDB...');
    mongoClient = await MongoClient.connect(process.env.MONGODB_URI);
    const db = mongoClient.db('abra_fleet');
    const collection = db.collection('onesignal_notifications');
    
    console.log('✅ Connected to MongoDB\n');
    
    // Get all Firebase notifications
    console.log('📥 Fetching Firebase notifications...');
    const snapshot = await firestore.collection('notifications').get();
    
    if (snapshot.empty) {
      console.log('❌ No notifications found in Firebase');
      console.log('\n💡 Nothing to migrate. Exiting...');
      return;
    }
    
    console.log(`✅ Found ${snapshot.size} notifications in Firebase\n`);
    console.log('='.repeat(80));
    console.log('Starting migration...\n');
    
    // Migrate each notification
    let migrated = 0;
    let skipped = 0;
    let errors = 0;
    
    for (const doc of snapshot.docs) {
      try {
        const firebaseData = doc.data();
        
        // Check if already migrated
        const existing = await collection.findOne({ 
          firebaseId: doc.id 
        });
        
        if (existing) {
          console.log(`⏭️  Skipping ${doc.id} (already migrated)`);
          skipped++;
          continue;
        }
        
        // Transform Firebase notification to MongoDB format
        const mongoNotification = {
          // Original Firebase ID for reference
          firebaseId: doc.id,
          
          // User information
          userId: firebaseData.userId || firebaseData.uid || 'unknown',
          userRole: firebaseData.userRole || firebaseData.role || 'customer',
          
          // Notification content
          type: firebaseData.type || 'system',
          title: firebaseData.title || 'Notification',
          message: firebaseData.message || firebaseData.body || '',
          body: firebaseData.body || firebaseData.message || '',
          
          // Additional data
          data: firebaseData.data || {},
          priority: firebaseData.priority || 'normal',
          category: firebaseData.category || 'general',
          
          // Status
          isRead: firebaseData.isRead || firebaseData.read || false,
          
          // Timestamps
          createdAt: firebaseData.createdAt?.toDate?.() || 
                     firebaseData.timestamp?.toDate?.() || 
                     (firebaseData.createdAt ? new Date(firebaseData.createdAt) : new Date()),
          readAt: firebaseData.readAt?.toDate?.() || null,
          
          // Migration metadata
          migratedFrom: 'firebase',
          migratedAt: new Date()
        };
        
        // Insert into MongoDB
        await collection.insertOne(mongoNotification);
        
        console.log(`✅ Migrated: ${doc.id}`);
        console.log(`   User: ${mongoNotification.userId}`);
        console.log(`   Type: ${mongoNotification.type}`);
        console.log(`   Title: ${mongoNotification.title}`);
        migrated++;
        
      } catch (error) {
        console.error(`❌ Error migrating ${doc.id}:`, error.message);
        errors++;
      }
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('📊 MIGRATION SUMMARY');
    console.log('='.repeat(80));
    console.log(`✅ Successfully migrated: ${migrated}`);
    console.log(`⏭️  Skipped (already migrated): ${skipped}`);
    console.log(`❌ Errors: ${errors}`);
    console.log(`📊 Total processed: ${snapshot.size}`);
    console.log('='.repeat(80));
    
    if (migrated > 0) {
      console.log('\n🎉 Migration completed successfully!');
      console.log('📱 Users can now see their old notifications in the app');
      console.log('\n📋 Next steps:');
      console.log('   1. Run: node verify-notification-migration.js');
      console.log('   2. Test in app - open notification screen');
      console.log('   3. Verify old notifications are visible');
    } else if (skipped > 0) {
      console.log('\n✅ All notifications were already migrated!');
      console.log('📱 Users should already see their old notifications in the app');
    }
    
  } catch (error) {
    console.error('\n❌ Migration failed:', error);
    console.log('\n💡 Troubleshooting:');
    console.log('   - Check MongoDB connection string in .env');
    console.log('   - Check Firebase credentials');
    console.log('   - Check network connectivity');
  } finally {
    if (mongoClient) {
      await mongoClient.close();
      console.log('\n📡 MongoDB connection closed');
    }
  }
}

// Run migration
migrateNotifications()
  .then(() => {
    console.log('\n✅ Migration script completed');
    process.exit(0);
  })
  .catch(error => {
    console.error('Fatal error:', error);
    process.exit(1);
  });
